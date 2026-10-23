' Ear Drama on Roku: the 1.0 stub (DECISIONS 056). One screen, Listen, read
' from the web projection's JSON (docs/CATALOG-CONTRACT.md section 4), the same
' files eardrama.org serves to the web app.
'
' The data base comes from the manifest's ed_data_base. A launch parameter
' data=<url> overrides it for development (a Mac on the LAN serving
' catalog/out/web), e.g. over ECP:
'   curl -d '' "http://$ROKU_HOST:8060/launch/dev?data=http%3A%2F%2F192.168.1.20%3A8431%2Fdata%2F"

sub Main(args as Dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.setMessagePort(port)
    scene = screen.CreateScene("MainScene")
    screen.show()

    info = CreateObject("roAppInfo")
    base = info.GetValue("ed_data_base")
    if args <> invalid and args.data <> invalid and args.data <> "" then base = args.data
    print "ED main: data base "; base
    scene.dataBase = base

    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent" and msg.isScreenClosed() then return
    end while
end sub
