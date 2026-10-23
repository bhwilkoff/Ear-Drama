' Listen's rows, read from the web projection (docs/CATALOG-CONTRACT.md section
' 4). The projection already decided what is served and in what order; this
' only reads it. Shelf names come from manifest.json's genreNames, never typed
' here. The meta line mirrors js/app.js seriesMeta: networks, years, episodes.

sub init()
    m.top.functionName = "load"
end sub

sub load()
    base = m.top.dataBase
    if base = invalid or base = "" then
        print "ED listen: no data base"
        m.top.state = "error"
        return
    end if
    if Right(base, 1) <> "/" then base = base + "/"

    listen = fetchJson(base + "index/listen.json")
    if listen = invalid or listen.fields = invalid then
        device = CreateObject("roDeviceInfo")
        if device.GetLinkStatus() = false then
            m.top.state = "offline"
        else
            m.top.state = "error"
        end if
        return
    end if

    names = {}
    manifest = fetchJson(base + "manifest.json")
    if manifest <> invalid and manifest.genreNames <> invalid then names = manifest.genreNames

    col = {}
    for i = 0 to listen.fields.Count() - 1
        col[listen.fields[i]] = i
    end for

    root = CreateObject("roSGNode", "ContentNode")
    addRow(root, "Most episodes", listen.most, col)
    if listen.shelves <> invalid then
        for each shelf in listen.shelves
            title = names[fmt(shelf.genre)]
            if title = invalid then title = fmt(shelf.genre)
            addRow(root, title, shelf.series, col)
        end for
    end if

    print "ED listen: rows "; root.getChildCount()
    if root.getChildCount() = 0 then
        m.top.state = "empty"
        return
    end if
    m.top.rows = root
    m.top.state = "ready"
end sub

sub addRow(root as Object, title as String, series as Dynamic, col as Object)
    if series = invalid or series.Count() = 0 then return
    row = root.CreateChild("ContentNode")
    row.title = title
    for each s in series
        item = row.CreateChild("ContentNode")
        item.id = fmt(s[col.key])
        item.title = fmt(s[col.name])
        item.shortDescriptionLine1 = seriesMeta(s, col)
    end for
end sub

function seriesMeta(s as Object, col as Object) as String
    parts = []
    nets = fmt(s[col.networks])
    if nets <> "" then parts.Push(nets)
    a = Left(fmt(s[col.first]), 4)
    b = Left(fmt(s[col.last]), 4)
    if a <> "" then
        if b = "" or b = a then
            parts.Push(a)
        else
            parts.Push(a + "–" + b)
        end if
    end if
    n = fmt(s[col.episodes])
    if n = "1" then
        parts.Push("1 episode")
    else if n <> "" then
        parts.Push(withCommas(n) + " episodes")
    end if
    return parts.Join(" · ")
end function

function withCommas(digits as String) as String
    out = ""
    rest = digits
    while Len(rest) > 3
        out = "," + Right(rest, 3) + out
        rest = Left(rest, Len(rest) - 3)
    end while
    return rest + out
end function

' Every printable value goes through here: Str() of a string is a runtime Type
' Mismatch, and a JSON null arrives as invalid.
function fmt(v as Dynamic) as String
    if v = invalid then return ""
    t = type(v)
    if t = "roString" or t = "String" then return v
    if t = "roInt" or t = "roInteger" or t = "Integer" or t = "LongInteger" or t = "roLongInteger" then return v.ToStr()
    if t = "roFloat" or t = "Float" or t = "Double" or t = "roDouble" then return v.ToStr()
    return ""
end function

function fetchJson(url as String) as Dynamic
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url)
    if LCase(Left(url, 6)) = "https:" then
        xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
        xfer.InitClientCertificates()
    end if
    xfer.EnableEncodings(true)
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    if not xfer.AsyncGetToString() then return invalid
    msg = wait(15000, port)
    if type(msg) <> "roUrlEvent" then
        xfer.AsyncCancel()
        print "ED listen: timeout "; url
        return invalid
    end if
    code = msg.GetResponseCode()
    print "ED listen: "; code; " "; url
    if code <> 200 then return invalid
    return ParseJson(msg.GetString())
end function
