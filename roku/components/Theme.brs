' The channel's look, from design-tokens.json's dark palette, with text held at
' 235 per channel (broadcast-safe; #FFFFFF fails certification). Type is Public
' Sans (DECISIONS 060), bundled because Roku's system font has no size of its own.
' Four of the six allowed levels are in use: display, title, body-strong, body.

function theme() as Object
    return {
        ground: "0x141619FF"
        text: "0xEBEBEBFF"
        muted: "0xA2A9B4FF"
        edge: "0x3A3F47FF"
        error: "0xFF8A80FF"
        display: makeFont("Bold", 64)
        title: makeFont("Bold", 40)
        bodyStrong: makeFont("SemiBold", 30)
        body: makeFont("Regular", 28)
    }
end function

function makeFont(weight as String, size as Integer) as Object
    f = CreateObject("roSGNode", "Font")
    f.uri = "pkg:/fonts/PublicSans-" + weight + ".ttf"
    f.size = size
    return f
end function
