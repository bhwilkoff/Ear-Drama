// The label's tokens (design-tokens.json art.label), generated from design-tokens.json by tools/design_tokens.mjs. Do not edit by hand.
package com.example.appname.data

object LabelTokens {
    val genres = listOf("drama", "mystery", "scifi", "western", "comedy", "news", "documentary", "serial")
    const val JSON = """
{
  "viewBox": 100,
  "tiers": {
    "M": 96,
    "L": 320
  },
  "dial": {
    "from": 1930,
    "to": 1962,
    "startDeg": 210,
    "sweepDeg": 240,
    "ticks": [
      1930,
      1940,
      1950,
      1960
    ]
  },
  "disc": {
    "r": 47,
    "opacity": 0.1
  },
  "grooves": {
    "from": 21,
    "to": {
      "M": 39.5,
      "L": 34
    },
    "step": {
      "M": 3.1,
      "L": 1.6
    },
    "width": 0.35,
    "opacity": 0.32
  },
  "ticks": {
    "r0": 40,
    "r1": 42.5,
    "width": 0.9,
    "opacity": 0.75
  },
  "arc": {
    "r": {
      "S": 43.5,
      "M": 44.75,
      "L": 44.75
    },
    "width": {
      "S": 7,
      "M": 4,
      "L": 3.5
    }
  },
  "evening": {
    "r0": {
      "S": 35,
      "M": 35,
      "L": 40
    },
    "r1": 47,
    "width": {
      "S": 3.2,
      "M": 1.8,
      "L": 1.4
    }
  },
  "label": {
    "r": {
      "S": 27,
      "M": 21,
      "L": 19
    },
    "fitW": 0.76,
    "fitH": 0.6,
    "small": 0.34,
    "lead": 0.55
  },
  "rim": {
    "r": 36.5,
    "size": 3.4,
    "tracking": 0.14,
    "opacity": 0.85,
    "maxSweepDeg": 150
  },
  "parts": {
    "r": {
      "S": 43.5,
      "M": 44.75,
      "L": 44.75
    },
    "width": {
      "S": 6,
      "M": 4,
      "L": 3.5
    },
    "backing": 1.4,
    "gapDeg": 4,
    "startDeg": 90
  },
  "person": {
    "ring": {
      "r": 40,
      "width": {
        "S": 2.6,
        "M": 1.6,
        "L": 1.2
      },
      "opacity": 0.55
    },
    "fitR": 25,
    "arc": {
      "r": 45,
      "width": 3
    }
  },
  "play": {
    "bands": [
      2,
      4,
      8
    ],
    "rule": {
      "x0": 8,
      "y": 93,
      "len": 9,
      "gap": 3,
      "width": 2.2,
      "opacity": 0.55,
      "foot": 86
    },
    "cast": {
      "x": 12,
      "w": 76,
      "h": 7,
      "hFirst": 11,
      "gap": 6,
      "max": 7,
      "minW": 10,
      "more": {
        "size": 10,
        "x": 92,
        "y": 94
      }
    },
    "board": "drama",
    "page": {
      "x0": 9,
      "span": 82,
      "mono": {
        "x": 8.4,
        "cap": {
          "S": 40,
          "M": 34,
          "L": 30
        },
        "y": {
          "S": 47,
          "M": 46,
          "L": 50
        }
      },
      "cols": {
        "max": {
          "S": 6,
          "M": 10,
          "L": 12
        },
        "gap": {
          "S": 3,
          "M": 2.2,
          "L": 1.6
        },
        "base": {
          "S": 88,
          "M": 82,
          "L": 82
        },
        "h": {
          "S": 32,
          "M": 26,
          "L": 26
        },
        "maxW": {
          "S": 16,
          "M": 13,
          "L": 13
        },
        "min": 0.08,
        "restOpacity": 0.42
      },
      "ruler": {
        "y": 92,
        "h": {
          "M": 3,
          "L": 2.2
        },
        "tick": 1.6,
        "width": 0.6,
        "opacity": 0.38,
        "inset": 0.8
      },
      "rim": {
        "x": 9,
        "y": 15,
        "size": 3.6,
        "tracking": 0.14,
        "opacity": 0.85
      },
      "eras": [
        "Antiquity",
        "Medieval",
        "1500s",
        "1600s",
        "1700s",
        "1800s",
        "1900-1930"
      ]
    }
  },
  "colors": {
    "groundNone": "brand.surfaceAlt",
    "onNone": "brand.text",
    "partNone": "brand.textMuted",
    "partsBacking": "brand.background",
    "playGround": "print.ground",
    "playInk": "brand.text"
  },
  "glyphs": {
    "tracking": 0.02,
    "display": {
      "1": 0.27,
      "cap": 0.8,
      "default": 0.5,
      "M": 0.76,
      "W": 0.78,
      "I": 0.27,
      ".": 0.25,
      "’": 0.25,
      " ": 0.22,
      "·": 0.2
    },
    "body": {
      "1": 0.43,
      "cap": 0.73,
      "default": 0.73,
      "M": 0.92,
      "W": 0.97,
      "G": 0.76,
      "H": 0.77,
      "N": 0.79,
      "O": 0.77,
      "Q": 0.78,
      "I": 0.31,
      "J": 0.41,
      ".": 0.27,
      "’": 0.27,
      " ": 0.23,
      "·": 0.26
    }
  }
}
"""
}
