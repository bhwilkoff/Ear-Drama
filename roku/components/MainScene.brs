sub init()
    m.t = theme()
    m.top.backgroundColor = m.t.ground
    m.top.backgroundUri = ""
    m.top.findNode("ground").color = m.t.ground

    heading = m.top.findNode("heading")
    heading.font = m.t.display
    heading.color = m.t.text

    m.rows = m.top.findNode("rows")
    m.rows.itemSize = [1728, 200]
    m.rows.rowItemSize = [[400, 200]]
    m.rows.rowItemSpacing = [[32, 0]]
    m.rows.itemSpacing = [0, 96]
    m.rows.numRows = 3
    m.rows.showRowLabel = [true]
    m.rows.rowLabelFont = m.t.title
    m.rows.rowLabelColor = m.t.text
    m.rows.rowLabelOffset = [[0, 16]]
    m.rows.focusBitmapUri = "pkg:/images/ring.9.png"
    m.rows.drawFocusFeedbackOnTop = true
    m.rows.rowFocusAnimationStyle = "floatingFocus"
    m.rows.vertFocusAnimationStyle = "floatingFocus"
    m.rows.observeField("rowItemSelected", "onSelect")

    m.spinner = m.top.findNode("spinner")
    m.spinner.poster.uri = "pkg:/images/spinner.png"
    m.spinner.spinInterval = 1

    m.problem = m.top.findNode("problem")
    m.problemText = m.top.findNode("problemText")
    m.problemText.font = m.t.body
    m.problemText.color = m.t.text
    m.retry = m.top.findNode("retry")
    m.retry.textFont = m.t.bodyStrong
    m.retry.focusedTextFont = m.t.bodyStrong
    m.retry.textColor = m.t.text
    m.retry.focusedTextColor = m.t.ground
    m.retry.iconUri = ""
    m.retry.focusedIconUri = ""
    m.retry.focusBitmapUri = "pkg:/images/pill.9.png"
    m.retry.showFocusFootprint = false
    m.retry.minWidth = 240
    m.retry.height = 72
    m.retry.observeField("buttonSelected", "onRetry")

    m.top.setFocus(true)
end sub

sub onDataBase()
    startLoad()
end sub

sub onRetry()
    startLoad()
end sub

sub startLoad()
    m.rows.visible = false
    m.problem.visible = false
    m.spinner.visible = true
    m.spinner.control = "start"
    m.retry.setFocus(false)
    m.top.setFocus(true)
    m.task = CreateObject("roSGNode", "ListenTask")
    m.task.dataBase = m.top.dataBase
    m.task.observeField("state", "onState")
    m.task.control = "run"
end sub

sub onState()
    outcome = m.task.state
    print "ED scene: "; outcome
    m.spinner.control = "stop"
    m.spinner.visible = false
    if outcome = "ready" then
        m.rows.content = m.task.rows
        m.rows.visible = true
        m.rows.setFocus(true)
        return
    end if
    if outcome = "empty" then
        m.problemText.text = "Nothing in the catalog yet."
    else if outcome = "offline" then
        m.problemText.text = "You are offline."
    else
        m.problemText.text = "This did not load."
    end if
    m.problem.visible = true
    m.retry.setFocus(true)
end sub

' A stub has no Series screen yet (PARITY: Roku is pending). The choice is
' traced so a harness can see the press arrive.
sub onSelect()
    sel = m.rows.rowItemSelected
    row = m.rows.content.getChild(sel[0])
    item = row.getChild(sel[1])
    print "ED select: "; item.id
end sub
