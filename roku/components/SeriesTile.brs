sub init()
    m.t = theme()
    m.edge = m.top.findNode("edge")
    m.name = m.top.findNode("name")
    m.meta = m.top.findNode("meta")
    m.edge.color = m.t.edge
    m.name.font = m.t.bodyStrong
    m.name.color = m.t.text
    m.meta.font = m.t.body
    m.meta.color = m.t.muted
    ' itemContent can arrive before init() has found the nodes; replay it.
    if m.top.itemContent <> invalid then onContent()
end sub

sub onContent()
    if m.name = invalid then return
    item = m.top.itemContent
    if item = invalid then return
    m.name.text = item.title
    m.meta.text = item.shortDescriptionLine1
end sub
