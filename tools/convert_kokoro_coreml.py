#!/usr/bin/env python3
"""Convert Kokoro-82M (Apache-2.0) to Core ML for the Apple apps (Decision 078, R2-kokoro-feasibility §6 S6e).

    python3.12 -m venv VENV && VENV/bin/pip install coremltools==9.0 torch==2.7.0 "numpy<2.3" huggingface_hub \
        loguru "transformers<4.50" && VENV/bin/pip install --no-deps kokoro==0.9.4
    VENV/bin/python tools/convert_kokoro_coreml.py WORK_DIR [--precision mixed|fp32|fp16] [--weights int8|none]

WORK_DIR needs `voices.bin`, the 28-voice table tools/publish_kokoro_model.py builds (for the check below).

Our own conversion, from hexgrad's PyTorch weights at a pinned revision: no third-party Swift package and no
third-party Core ML export. Two models, because Kokoro's frame count comes from its own duration prediction:

  KokoroDuration.mlpackage  input_ids (1, T) int32 (zero-padded), ref_s (1, 256), speed (1,), length (1,) tokens
                            -> duration (1, T) frames per token before rounding, d (1, T, 640), t_en (1, 512, T)
  KokoroDecoder.mlpackage   en (1, 640, F), asr (1, 512, F) (zero-padded), ref_s (1, 256), noise (1, 600 F, 1),
                            length (1,) frames -> audio (1, 600 F) at 24 kHz; the first 600 x length samples are the line

The app rounds the durations (at least 1 frame each), repeats each token's column of d and t_en for its frames
(Kokoro's alignment matrix, as a gather), and supplies Gaussian noise for the excitation, so no random operator is in
a graph and a render can be compared exactly.

Fixed shapes, one Core ML function per bucket (T in TOKEN_BUCKETS, F in FRAME_BUCKETS, weights shared): measured on
an M3, the decoder with flexible lengths ran 14x slower on the CPU and Core ML's GPU path refused it. A padded line
must sound exactly like the line alone, so every place padding could reach the valid frames is masked, using
`length`: instance norms take their statistics over the valid frames only; every convolution reads zeros past the
end, as it would unpadded; each bidirectional LSTM runs its backward direction over the valid frames reversed (a
gather); the source signal and its STFT replicate the last valid sample, as kokoro's own padding does; the inverse
STFT reads nothing past the end. The check below compares every bucket with the unpadded line.

Equivalences with kokoro's own modules on one line (batch 1):
  - pack_padded_sequence is replaced by the masking above;
  - the source's random initial phase is dropped: it is added to the first sample only and the linear downsample
    by 300 reads samples 149 and 150, so it never reached the output;
  - the 9 harmonics' Gaussian noise, merged by one linear layer, is one Gaussian scaled by that layer's weight norm;
  - weight norm is folded into plain weights; the STFT is kokoro's CustomSTFT (convolutions, disable_complex=True).

Writes WORK_DIR/KokoroDuration.mlpackage, KokoroDecoder.mlpackage (multifunction: `t32`, `f64`, ...) and
kokoro-coreml-report.json (sizes, SHA-256, the error measured); tools/publish_kokoro_model.py --coreml WORK_DIR
publishes them. Refuses a model whose audio has a non-finite sample or that drifts from PyTorch.

On macOS 27 coremltools 9.0 segfaults loading any Core ML model (MLModel.__init__, with or without torch in the
process; Python crash reports 2026-11-15/16), so step 4 cannot run on the owner's Mac and must not be retried there: the
conversion and steps 1-2 finish, the verify exits 245. The Swift engine is the check instead (apple/Tests/
KokoroBenchTests.swift, docs/research/design/kokoro-spike/coreml_asr_check.py). Known waste, not yet fixed: every
`torch.zeros_like` / `full_like` / scalar on a select's other side is folded into a constant of the bucket's whole
shape, one per function, and the int8 pass stores each: about 48 MB of the decoder's 112 MB weight.bin (2026-11-16).
Deriving the filler from a runtime tensor (the mask) should remove it; untested, as the conversion needs a Mac where
coremltools runs.
"""
import hashlib
import json
import math
import os
import shutil
import sys
import time

import numpy as np

HF = "hexgrad/Kokoro-82M"
REV = "f3ff3571791e39611d31c381e3a41a3af07b4987"
TOKEN_BUCKETS = [32, 64, 128]
FRAME_BUCKETS = [64, 128, 192, 256, 384, 512]
LINES = [  # phonemes of real lines as the catalog publishes them (misaki), short to long
    "kˈʌm ˈɪn.",
    "hˌæz ˈɛniwˌʌn spˈOkən jˈɛt?",
    "ðə kwˈɔlɪTi ʌv mˈɜɹsi ɪz nˌɑt stɹˈAnd. ɪt dɹˈɑpəθ æz ðə dʒˈɛntəl ɹˈAn fɹʌm hˈɛvən.",
    "mˈuv ˌɔn ˌʌp, mˈuv ˌɔn, mˈuv ˌɔn, tə ɡɛt wɪðˈɪn ðə kˈɑnsəkɹˌATᵻd ˈɛɹiə. ˈɛf ʃˈɔɹtli bəfˈɔɹ ðə mˈiTɪŋ ʌv ði",
]


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def load_kmodel(work):
    import importlib.util
    import types
    import torch
    from huggingface_hub import hf_hub_download
    # kokoro/__init__ imports its G2P pipeline (misaki); the model needs none of it.
    spec = importlib.util.find_spec("kokoro")
    pkg = types.ModuleType("kokoro")
    pkg.__path__ = list(spec.submodule_search_locations)
    sys.modules["kokoro"] = pkg
    from kokoro.model import KModel
    cache = os.path.join(work, "hf")
    config = hf_hub_download(HF, "config.json", revision=REV, cache_dir=cache)
    weights = hf_hub_download(HF, "kokoro-v1_0.pth", revision=REV, cache_dir=cache)
    km = KModel(repo_id=HF, config=config, model=weights, disable_complex=True).eval()
    for m in km.modules():
        if hasattr(m, "weight_g"):
            torch.nn.utils.remove_weight_norm(m)
    return km, json.load(open(config)), weights


def build(km):
    """The two wrappers, sharing kokoro's modules (and so its weights)."""
    import torch
    import torch.nn as nn
    import torch.nn.functional as F
    import kokoro.istftnet as ist

    def index(length):
        # A traced constant, not aten::arange: the converter lowers arange to a float range, which an fp16 model
        # then compares in fp16 (it counts exactly only to 2,048) and the masks and gathers go wrong.
        return torch.from_numpy(np.arange(length, dtype=np.int32))

    class Ctx:
        """The valid length of the model run now, at its base rate (tokens or frames); masks at any multiple of it.
        Every index is an int32 (`index`): an fp16 model counts exactly only to 2,048 and not at all past 65,504,
        and the source runs 600 x 512 samples (fp16 masks silenced the 384-frame bucket and blurred the rest)."""
        n = None
        base = None

        def valid(self, length):  # int32, shape (1,)
            if self.base is None:  # kokoro's own forward (the check below): nothing is padded
                return torch.tensor([length], dtype=torch.int32)
            n = self.n.to(torch.int32)
            if length % self.base == 0:
                return n * (length // self.base)
            if length % self.base == 1:  # the generator's reflection pad and STFT frames: k * base + 1
                return n * ((length - 1) // self.base) + 1
            raise ValueError(f"length {length} is not a multiple of {self.base}")

        def mask(self, length):  # (1, 1, length) bool
            return index(length).view(1, 1, length) < self.valid(length).view(1, 1, 1)

        def keep(self, x):  # x (1, C, L): zeros past the valid end (a select, so a non-finite value never leaks)
            return torch.where(self.mask(x.shape[-1]), x, torch.zeros_like(x))

        def last(self, length, scale):  # indices 0..L-1 clamped at the last valid one (replicate padding)
            i = index(length)
            return torch.minimum(i, self.n.to(torch.int32) * scale - 1).to(torch.int64)

    ctx = Ctx()

    def adain_forward(self, x, s):  # rsqrt(tensor(2)) is an integer tensor to the converter: the same as a float
        return (self._residual(x, s) + self._shortcut(x)) * (1.0 / math.sqrt(2.0))
    ist.AdainResBlk1d.forward = adain_forward

    class MaskedIN(nn.Module):
        """InstanceNorm1d (affine, biased variance) over the valid frames only."""
        def __init__(self, norm):
            super().__init__()
            self.weight, self.bias, self.eps = norm.weight, norm.bias, norm.eps

        def forward(self, x):
            m = ctx.mask(x.shape[-1])
            cnt = ctx.valid(x.shape[-1]).view(1, 1, 1).to(x.dtype)
            zero = torch.zeros_like(x)
            mean = torch.where(m, x / cnt, zero).sum(-1, keepdim=True)  # divided first: no fp16 overflow in the sum
            d = torch.where(m, x - mean, zero)
            var = (d * (d / cnt)).sum(-1, keepdim=True)
            y = (x - mean) * torch.rsqrt(var + self.eps)
            return y * self.weight.view(1, -1, 1) + self.bias.view(1, -1, 1)

    class BiLSTM(nn.Module):
        """A bidirectional LSTM over the valid steps: forward as is, backward over the valid steps reversed."""
        def __init__(self, lstm):
            super().__init__()
            self.f = nn.LSTM(lstm.input_size, lstm.hidden_size, batch_first=True)
            self.b = nn.LSTM(lstm.input_size, lstm.hidden_size, batch_first=True)
            for name in ("weight_ih_l0", "weight_hh_l0", "bias_ih_l0", "bias_hh_l0"):
                getattr(self.f, name).data.copy_(getattr(lstm, name).data)
                getattr(self.b, name).data.copy_(getattr(lstm, name + "_reverse").data)

        def forward(self, x):  # (1, T, C)
            t = x.shape[1]
            i = index(t)
            n = ctx.valid(t)
            rev = torch.where(i < n, n - 1 - i, i).to(torch.int64)
            f, _ = self.f(x)
            b, _ = self.b(x.index_select(1, rev))
            return torch.cat([f, b.index_select(1, rev)], dim=-1)

    for mod in list(km.predictor.modules()) + list(km.decoder.modules()):
        if isinstance(mod, ist.AdaIN1d):
            mod.norm = MaskedIN(mod.norm)
    for owner in (km.predictor.F0, km.predictor.N, km.decoder):
        for mod in owner.modules():
            if isinstance(mod, (nn.Conv1d, nn.ConvTranspose1d)):
                mod.register_forward_pre_hook(lambda _, inp: (ctx.keep(inp[0]),) + tuple(inp[1:]))

    class Duration(nn.Module):
        def __init__(self):
            super().__init__()
            self.bert, self.bert_encoder = km.bert, km.bert_encoder
            self.lstms = km.predictor.text_encoder.lstms
            self.bilstms = nn.ModuleList([BiLSTM(b) for b in self.lstms if isinstance(b, nn.LSTM)])
            self.pred_lstm, self.proj = BiLSTM(km.predictor.lstm), km.predictor.duration_proj
            self.te, self.te_lstm = km.text_encoder, BiLSTM(km.text_encoder.lstm)

        def forward(self, input_ids, ref_s, speed, length):
            T = input_ids.shape[-1]
            ctx.base, ctx.n = T, length
            m = ctx.mask(T)  # 1, 1, T
            ids = input_ids.long()
            emb = self.bert.embeddings(ids, token_type_ids=torch.zeros_like(ids))
            ext = (m.to(torch.float32) - 1.0).view(1, 1, 1, T) * 10000.0  # fp16-safe additive mask
            h = self.bert.encoder(emb, ext)[0]
            d_en = self.bert_encoder(h).transpose(-1, -2)  # 1, 512, T
            s = ref_s[:, 128:]
            sx = s.unsqueeze(-1).expand(-1, -1, T)
            x = ctx.keep(torch.cat([d_en, sx], dim=1))  # 1, 640, T
            k = 0
            for block in self.lstms:
                if isinstance(block, nn.LSTM):
                    x = ctx.keep(self.bilstms[k](x.transpose(-1, -2)).transpose(-1, -2))
                    k += 1
                else:
                    x = ctx.keep(torch.cat([block(x.transpose(-1, -2), s).transpose(-1, -2), sx], dim=1))
            d = x.transpose(-1, -2)  # 1, T, 640
            duration = torch.sigmoid(self.proj(self.pred_lstm(d))).sum(dim=-1) / speed
            t = ctx.keep(self.te.embedding(ids).transpose(1, 2))
            for c in self.te.cnn:
                t = ctx.keep(c(t))
            t = ctx.keep(self.te_lstm(t.transpose(1, 2)).transpose(-1, -2))
            return duration, d, t

    gen = km.decoder.generator

    class Decoder(nn.Module):
        def __init__(self):
            super().__init__()
            self.predictor, self.dec, self.gen = km.predictor, km.decoder, gen
            self.shared = BiLSTM(km.predictor.shared)
            self.register_buffer("harmonics", torch.arange(1, 10, dtype=torch.float32).view(1, 1, 9))
            self.wnorm = float(gen.m_source.l_linear.weight.detach().norm())

        def forward(self, en, asr, ref_s, noise, length):
            Fb = en.shape[-1]
            ctx.base, ctx.n = Fb, length
            s, sref = ref_s[:, 128:], ref_s[:, :128]
            p = self.predictor
            x = ctx.keep(self.shared(en.transpose(-1, -2)).transpose(-1, -2))  # 1, 512, F
            f0, n = x, x
            for block in p.F0:
                f0 = block(f0, s)
            for block in p.N:
                n = block(n, s)
            f0, n = p.F0_proj(f0).squeeze(1), p.N_proj(n).squeeze(1)  # 1, 2F
            d = self.dec
            F0 = d.F0_conv(f0.unsqueeze(1))
            N = d.N_conv(n.unsqueeze(1))
            x = d.encode(torch.cat([asr, F0, N], dim=1), sref)
            asr_res = d.asr_res(asr)
            res = True
            for block in d.decode:
                if res:
                    x = torch.cat([x, asr_res, F0, N], dim=1)
                x = block(x, sref)
                if block.upsample_type != "none":
                    res = False
            g, up = self.gen, 300
            # The source: harmonics of the F0 curve (replicated past the end, as interpolation clamps there).
            f0c = f0.index_select(-1, ctx.last(2 * Fb, 2))
            rad = torch.remainder(f0c.unsqueeze(-1) * self.harmonics / 24000.0, 1.0)  # 1, 2F, 9
            phase = torch.cumsum(rad, dim=1) * (2 * math.pi)
            uv_low = (f0c.unsqueeze(-1) > 10).to(torch.float32)
            # One linear upsample for both: thresholding the interpolated voicing at 0.5 is exactly nearest.
            hi = F.interpolate(torch.cat([phase * up, uv_low], dim=-1).transpose(1, 2), scale_factor=float(up),
                               mode="linear").transpose(1, 2)  # 1, 600F, 10
            sines = torch.sin(hi[..., :9]) * 0.1
            uv = (hi[..., 9:] > 0.5).to(torch.float32)
            amp = uv * 0.003 + (1 - uv) * (0.1 / 3)
            har = torch.tanh(g.m_source.l_linear(sines * uv) + amp * self.wnorm * noise).squeeze(-1)  # 1, 600F
            har = har.index_select(-1, ctx.last(600 * Fb, 600))
            st = g.stft
            wav = F.pad(har, (st.n_fft // 2, st.n_fft // 2), mode="replicate").unsqueeze(1)
            re = F.conv1d(wav, st.weight_forward_real, stride=st.hop_length)
            im = F.conv1d(wav, st.weight_forward_imag, stride=st.hop_length)
            mag = torch.sqrt(re * re + im * im + 1e-14)
            ph = torch.atan2(im, re)
            ph = torch.where((im == 0) & (re < 0), torch.full_like(ph, math.pi), ph)
            hs = torch.cat([mag, ph], dim=1)
            for i in range(g.num_upsamples):
                x = F.leaky_relu(x, negative_slope=0.1)
                xs_ = g.noise_res[i](g.noise_convs[i](hs), sref)
                x = g.ups[i](x)
                if i == g.num_upsamples - 1:
                    x = g.reflection_pad(x)
                x = x + xs_
                acc = None
                for j in range(g.num_kernels):
                    r = g.resblocks[i * g.num_kernels + j](x, sref)
                    acc = r if acc is None else acc + r
                x = acc / g.num_kernels
            x = g.conv_post(F.leaky_relu(x))
            nb = g.post_n_fft // 2 + 1
            spec = torch.exp(x[:, :nb, :])
            pha = torch.sin(x[:, nb:, :])
            out = F.conv_transpose1d(ctx.keep(spec * torch.cos(pha)), st.weight_backward_real, stride=st.hop_length) - \
                F.conv_transpose1d(ctx.keep(spec * torch.sin(pha)), st.weight_backward_imag, stride=st.hop_length)
            pad = st.n_fft // 2
            return out[:, 0, pad:-pad]

    def unmasked(fn):
        def run(*a, **k):
            ctx.base = ctx.n = None
            return fn(*a, **k)
        return run
    km.forward_with_tokens = unmasked(km.forward_with_tokens)
    return Duration().eval(), Decoder().eval()


def keep_fp32(op):
    """The ops a mixed model computes in fp32, the rest in fp16. The source's phase is a running sum that reaches
    thousands of radians (fp16 holds a step of 4 there, so its sines are noise), and the inverse STFT's exp
    overflows fp16 (the NaN renders, R2-kokoro-feasibility §3). Both run on tensors no other part of the model
    has: 9 harmonics, 10 with the voicing, 11 or 22 STFT bins, and a single channel at the audio rate."""
    if op.op_type in ("cumsum", "exp", "floor_mod", "mod"):
        return True
    for o in op.outputs:
        sh = getattr(o, "shape", None)
        if sh is not None and len(sh) == 3 and (sh[-1] in (1, 9, 10) or sh[1] in (1, 9, 10, 11, 22)):
            return True
    return False


def pad_to(a, axis, size):
    w = [(0, 0)] * a.ndim
    w[axis] = (0, size - a.shape[axis])
    return np.pad(a, w)


def align(duration, d, t_en, n):
    """Kokoro's alignment over the first n (valid) tokens: en (1, 640, F), asr (1, 512, F), F."""
    dur = np.maximum(np.round(duration[0][:n]), 1).astype(np.int64)
    idx = np.repeat(np.arange(n), dur)
    return d[0][idx].T[None].astype(np.float32), t_en[0][:, idx][None].astype(np.float32), int(len(idx))


def snr_db(want, got):
    n = min(len(want), len(got))
    err = float(np.sum((want[:n] - got[:n]) ** 2))
    return 10 * math.log10(float(np.sum(want[:n] ** 2)) / max(err, 1e-20))


def spec_snr_db(want, got):
    """Signal-to-error of the magnitude spectra (1024-point frames, hop 256): blind to phase, which the vocoder
    amplifies from any last-digit difference, and so the measure of two renders that sound alike."""
    n = min(len(want), len(got))
    if n < 1024:
        return snr_db(want, got)
    win = np.hanning(1024).astype(np.float32)

    def mag(x):
        frames = np.lib.stride_tricks.sliding_window_view(x[:n], 1024)[::256] * win
        return np.abs(np.fft.rfft(frames, axis=-1))
    a, b = mag(want), mag(got)
    return 10 * math.log10(float(np.sum(a ** 2)) / max(float(np.sum((a - b) ** 2)), 1e-20))


def tokens(vocab, ps):
    return np.array([[0] + [vocab[c] for c in ps if c in vocab] + [0]], dtype=np.int32)


def bucket(n, buckets):
    return next(b for b in buckets if b >= n)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        sys.exit(__doc__)
    opt = lambda k, d: sys.argv[sys.argv.index(k) + 1] if k in sys.argv else d
    precision, wq = opt("--precision", "mixed"), opt("--weights", "int8")
    global TOKEN_BUCKETS, FRAME_BUCKETS
    if "--tokens" in sys.argv:  # experiments only: fewer functions convert faster
        TOKEN_BUCKETS = [int(x) for x in opt("--tokens", "").split(",")]
    if "--frames" in sys.argv:
        FRAME_BUCKETS = [int(x) for x in opt("--frames", "").split(",")]
    if "--verify" in sys.argv:
        return verify(os.path.abspath(args[0]), precision, wq, opt("--units", "all"))
    import faulthandler
    faulthandler.enable()
    work = os.path.abspath(args[0])
    os.makedirs(work, exist_ok=True)
    import torch
    import coremltools as ct
    from coremltools.models.utils import MultiFunctionDescriptor, save_multifunction
    torch.manual_seed(0)
    km, config, weights = load_kmodel(work)
    vocab = config["vocab"]
    dur_m, dec_m = build(km)
    voices = os.path.join(work, "voices.bin")
    if not os.path.exists(voices):
        sys.exit(f"{voices}: the 28-voice table (tools/publish_kokoro_model.py builds it) is needed for the check")
    table = np.fromfile(voices, dtype="<f4").reshape(28, 510, 256)
    rng = np.random.default_rng(0)
    report = {"source": f"https://huggingface.co/{HF}/tree/{REV}", "weights_sha256": sha(weights), "lines": [],
              "token_buckets": TOKEN_BUCKETS, "frame_buckets": FRAME_BUCKETS}

    def torch_line(ps, vi, noise=None, tb=None, fb=None):
        """The wrappers on one line, unpadded unless buckets are given: (audio, frames, noise)."""
        ids = tokens(vocab, ps)
        n = ids.shape[1]
        ref = torch.from_numpy(table[vi, n - 2][None].copy())
        with torch.no_grad():
            du, d, t = dur_m(torch.from_numpy(pad_to(ids, 1, tb or n)), ref, torch.tensor([1.0]), torch.tensor([float(n)]))
            en, asr, nf = align(du.numpy(), d.numpy(), t.numpy(), n)
            if noise is None:
                noise = rng.standard_normal((1, 600 * nf, 1)).astype(np.float32)
            F = fb or nf
            a = dec_m(torch.from_numpy(pad_to(en, 2, F)), torch.from_numpy(pad_to(asr, 2, F)), ref,
                      torch.from_numpy(pad_to(noise, 1, 600 * F)), torch.tensor([float(nf)]))[0].numpy()
        return a[:600 * nf], nf, noise

    # 1. The unpadded wrappers against kokoro's own forward (noise zero on both sides).
    with torch.no_grad():
        ids = tokens(vocab, LINES[2])
        ref = torch.from_numpy(table[0, ids.shape[1] - 2][None].copy())
        real_randn, real_rand = torch.randn_like, torch.rand
        torch.randn_like = lambda x, *a, **k: torch.zeros_like(x)
        torch.rand = lambda *a, **k: torch.zeros(*[s for s in a if isinstance(s, int)])
        try:
            want, _ = km.forward_with_tokens(torch.from_numpy(ids).long(), ref, 1.0)
        finally:
            torch.randn_like, torch.rand = real_randn, real_rand
    got, nf, _ = torch_line(LINES[2], 0, noise=np.zeros((1, 0, 1), np.float32))
    snr = snr_db(want.numpy(), got)
    # The decoder alone matches kokoro's to the bit; the LSTMs' last-digit differences (1e-6) are amplified by the
    # vocoder, so a whole line is compared by signal-to-noise, not by sample.
    print(f"wrapper vs kokoro: {nf} frames, SNR {snr:.1f} dB", flush=True)
    report["wrapper_snr_db"] = round(snr, 1)
    if snr < 30:
        sys.exit("the wrapper does not match kokoro's forward")

    # 2. Padding changes nothing: each line in a bigger bucket against the same line unpadded.
    worst_pad = 99.0
    for ps in LINES:
        base, nf, noise = torch_line(ps, 16)
        n = tokens(vocab, ps).shape[1]
        for tb, fb in ((bucket(n, TOKEN_BUCKETS), bucket(nf, FRAME_BUCKETS)), (TOKEN_BUCKETS[-1], FRAME_BUCKETS[-1])):
            padded, nf2, _ = torch_line(ps, 16, noise=noise, tb=tb, fb=fb)
            s = snr_db(base, padded) if nf2 == nf else -1.0
            worst_pad = min(worst_pad, s)
            print(f"padded T {n}->{tb}, F {nf}->{fb}: SNR {s:.1f} dB", flush=True)
    report["padding_worst_snr_db"] = round(worst_pad, 1)
    if worst_pad < 30:
        sys.exit("padding changes the audio: a mask is missing")

    out = {n: os.path.join(work, n + ".mlpackage") for n in ("KokoroDuration", "KokoroDecoder")}
    cp = {"fp32": ct.precision.FLOAT32, "fp16": ct.precision.FLOAT16}.get(precision)
    if precision == "mixed":
        cp = ct.transform.FP16ComputePrecision(op_selector=lambda op: not keep_fp32(op))
    if "--check-only" not in sys.argv:
        # 3. One converted function per bucket, merged into one package each (weights stored once).
        common = dict(convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18, compute_precision=cp)
        if wq == "int8":
            from coremltools.optimize.coreml import OpLinearQuantizerConfig, OptimizationConfig, linear_quantize_weights
            qc = OptimizationConfig(global_config=OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8",
                                                                           granularity="per_channel", weight_threshold=2048))
        meta = {"source": f"https://huggingface.co/{HF}/tree/{REV}", "license": "Apache-2.0",
                "converter": "tools/convert_kokoro_coreml.py", "precision": precision, "weights": wq}
        parts = os.path.join(work, "parts")
        shutil.rmtree(parts, ignore_errors=True)
        os.makedirs(parts)
        t0 = time.time()
        ref = torch.zeros(1, 256)
        for name, buckets, key in (("KokoroDuration", TOKEN_BUCKETS, "t"), ("KokoroDecoder", FRAME_BUCKETS, "f")):
            desc = MultiFunctionDescriptor()
            for b in buckets:
                with torch.no_grad():
                    if key == "t":
                        ex = (torch.zeros(1, b, dtype=torch.int32), ref, torch.tensor([1.0]), torch.tensor([float(b)]))
                        tr = torch.jit.trace(dur_m, ex, check_trace=False)
                        ins = [ct.TensorType("input_ids", shape=(1, b), dtype=np.int32),
                               ct.TensorType("ref_s", shape=(1, 256), dtype=np.float32),
                               ct.TensorType("speed", shape=(1,), dtype=np.float32),
                               ct.TensorType("length", shape=(1,), dtype=np.float32)]
                        outs = [ct.TensorType("duration"), ct.TensorType("d"), ct.TensorType("t_en")]
                    else:
                        ex = (torch.zeros(1, 640, b), torch.zeros(1, 512, b), ref, torch.zeros(1, 600 * b, 1),
                              torch.tensor([float(b)]))
                        tr = torch.jit.trace(dec_m, ex, check_trace=False)
                        ins = [ct.TensorType("en", shape=(1, 640, b), dtype=np.float32),
                               ct.TensorType("asr", shape=(1, 512, b), dtype=np.float32),
                               ct.TensorType("ref_s", shape=(1, 256), dtype=np.float32),
                               ct.TensorType("noise", shape=(1, 600 * b, 1), dtype=np.float32),
                               ct.TensorType("length", shape=(1,), dtype=np.float32)]
                        outs = [ct.TensorType("audio")]
                m = ct.convert(tr, inputs=ins, outputs=outs, **common)
                if wq == "int8":
                    m = linear_quantize_weights(m, qc)
                p = os.path.join(parts, f"{name}-{key}{b}.mlpackage")
                m.save(p)
                desc.add_function(p, src_function_name="main", target_function_name=f"{key}{b}")
                print(f"{name} {key}{b} converted ({time.time() - t0:.0f} s)", flush=True)
            desc.default_function_name = f"{key}{buckets[0]}"
            merged = os.path.join(parts, name + ".mlpackage")
            save_multifunction(desc, merged)
            m = ct.models.MLModel(merged, skip_model_load=True)
            m.author, m.license = "hexgrad (Kokoro-82M); converted by Ear Drama", "Apache-2.0"
            m.user_defined_metadata.update(meta)
            shutil.rmtree(out[name], ignore_errors=True)
            m.save(out[name])
        shutil.rmtree(parts, ignore_errors=True)

    # 4. Core ML against the unpadded PyTorch line (same noise), every bucket a line falls in, three voices. The
    # PyTorch side is computed here and the Core ML side in a process without torch: loading Core ML functions
    # beside the PyTorch model crashed coremltools (a segfault in MLModel's load) on an 8 GB Mac.
    cases = {}
    k = 0
    for li, ps in enumerate(LINES):
        for vi in (0, 16, 26):
            want, nf, noise = torch_line(ps, vi)
            ids = tokens(vocab, ps)
            n = ids.shape[1]
            ref = table[vi, n - 2][None].astype(np.float32)
            with torch.no_grad():
                du, d, t = dur_m(torch.from_numpy(ids), torch.from_numpy(ref), torch.tensor([1.0]), torch.tensor([float(n)]))
            en_t, asr_t, _ = align(du.numpy(), d.numpy(), t.numpy(), n)
            for key, v in dict(want=want, noise=noise, ids=ids, ref=ref, en=en_t, asr=asr_t,
                               meta=np.array([li, vi, nf, n])).items():
                cases[f"{k}_{key}"] = v
            k += 1
    np.savez(os.path.join(work, "check-cases.npz"), count=np.array([k]), **cases)
    json.dump(report, open(os.path.join(work, "kokoro-coreml-report.json"), "w"), indent=1)
    import subprocess
    r = subprocess.run([sys.executable, os.path.abspath(__file__), work, "--verify", "--precision", precision,
                        "--weights", wq, "--units", opt("--units", "all")])
    sys.exit(r.returncode)


def verify(work, precision, wq, units):
    """The Core ML half of the check (no torch in this process): writes the report's lines, sizes and SHA-256."""
    import coremltools as ct
    import faulthandler
    faulthandler.enable()
    report = json.load(open(os.path.join(work, "kokoro-coreml-report.json")))
    global TOKEN_BUCKETS, FRAME_BUCKETS
    TOKEN_BUCKETS, FRAME_BUCKETS = report["token_buckets"], report["frame_buckets"]
    z = np.load(os.path.join(work, "check-cases.npz"))
    out = {n: os.path.join(work, n + ".mlpackage") for n in ("KokoroDuration", "KokoroDecoder")}
    cu = {"cpu": ct.ComputeUnit.CPU_ONLY, "gpu": ct.ComputeUnit.CPU_AND_GPU, "ane": ct.ComputeUnit.CPU_AND_NE,
          "all": ct.ComputeUnit.ALL}[units]
    models = {}

    def model(name, fn):
        if (name, fn) not in models:
            models[(name, fn)] = ct.models.MLModel(out[name], compute_units=cu, function_name=fn)
        return models[(name, fn)]

    worst = 99.0
    report["lines"] = []
    for k in range(int(z["count"][0])):
        c = lambda key: z[f"{k}_{key}"]
        li, vi, nf, n = (int(x) for x in c("meta"))
        want, noise, ids, ref = c("want"), c("noise"), c("ids"), c("ref")
        tb = bucket(n, TOKEN_BUCKETS)
        model("KokoroDuration", f"t{tb}")  # loaded (and compiled) before the clock starts
        t0 = time.time()
        r = model("KokoroDuration", f"t{tb}").predict({"input_ids": pad_to(ids, 1, tb), "ref_s": ref,
                                                       "speed": np.array([1.0], np.float32),
                                                       "length": np.array([n], np.float32)})
        en, asr, nf2 = align(r["duration"], r["d"], r["t_en"], n)
        if nf2 != nf:  # a duration rounding edge: the decoder is compared on the PyTorch alignment
            en, asr = c("en"), c("asr")
        fb = bucket(nf, FRAME_BUCKETS)
        a = model("KokoroDecoder", f"f{fb}").predict({
            "en": pad_to(en, 2, fb), "asr": pad_to(asr, 2, fb), "ref_s": ref,
            "noise": pad_to(noise, 1, 600 * fb), "length": np.array([nf], np.float32)})["audio"][0][:600 * nf]
        secs = time.time() - t0
        finite = bool(np.isfinite(a).all())
        snr = spec_snr_db(want, a) if finite else -99.0
        row = {"line": li, "voice": vi, "tokens": n, "frames": nf, "coreml_frames": nf2, "buckets": [tb, fb],
               "finite": finite, "peak": round(float(np.abs(a).max()), 3) if finite else None,
               "wave_snr_db": round(snr_db(want, a), 1) if finite else None, "spec_snr_db": round(snr, 1),
               "mac_seconds": round(secs, 3), "rtf_mac": round(secs / (nf * 0.025), 3)}
        report["lines"].append(row)
        print(row, flush=True)
        if not finite:
            sys.exit("refused: the Core ML model rendered a non-finite sample")
        worst = min(worst, snr)
    report["worst_spec_snr_db"] = round(worst, 1)
    files = []
    for name, p in out.items():
        for root, dirs, fs in os.walk(p):
            dirs.sort()
            for f in sorted(fs):
                full = os.path.join(root, f)
                files.append({"place": os.path.relpath(full, work), "bytes": os.path.getsize(full), "sha256": sha(full)})
    report.update(precision=precision, weights=wq, files=files, total_bytes=sum(f["bytes"] for f in files))
    json.dump(report, open(os.path.join(work, "kokoro-coreml-report.json"), "w"), indent=1)
    os.remove(os.path.join(work, "check-cases.npz"))
    print(json.dumps({k: report[k] for k in ("precision", "weights", "worst_spec_snr_db", "total_bytes")}))
    if worst < 15:
        sys.exit("refused: the Core ML audio drifts from PyTorch (spectral SNR under 15 dB)")


if __name__ == "__main__":
    main()
