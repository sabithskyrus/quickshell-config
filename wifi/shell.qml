import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

PanelWindow {
    id: root
    implicitWidth: 450
    implicitHeight: 600
    color: "transparent"

    // lets the password field receive keyboard input
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // ---------- State ----------
    property bool wifiOn: true
    property bool connected: false
    property string ssid: ""
    property int strength: 0
    property var networks: []          // other networks (not the connected one)
    property string selectedSsid: ""   // network whose password box is open
    property string status: ""         // message shown at the bottom

    property bool showDetails: false
    readonly property bool expanded: showDetails && connected
    property var info: ({})            // wifi details (band, channel, speed...)
    property var ipInfo: ({})          // IP details (address, gateway, DNS...)

    // ---------- Logic ----------
    // Parses lines like  yes:40:WPA2:REBELS-5G
    function parse(output) {
        let best = {}
        let active = null

        for (let line of output.trim().split("\n")) {
            if (!line) continue
            let parts = line.replace(/\\:/g, "\u0001").split(":")
            if (parts.length < 4) continue

            let isActive = parts[0] === "yes"
            let str = parseInt(parts[1])
            let secure = parts[2] !== "" && parts[2] !== "--"
            let name = parts.slice(3).join(":").replace(/\u0001/g, ":")
            if (name === "") continue

            if (isActive) {
                active = { ssid: name, strength: str }
                continue
            }
            // same network can appear several times (2.4 + 5 GHz): keep the strongest
            if (!best[name] || best[name].strength < str)
                best[name] = { ssid: name, strength: str, secure: secure }
        }

        if (active) {
            root.connected = true
            root.ssid = active.ssid
            root.strength = active.strength
        } else {
            root.connected = false
            root.ssid = ""
            root.strength = 0
            root.showDetails = false
        }

        let list = Object.values(best).filter(n => !active || n.ssid !== active.ssid)
        list.sort((a, b) => b.strength - a.strength)
        root.networks = list
    }

    function scan() {
        if (!wifiProc.running) wifiProc.running = true
        if (!radioState.running) radioState.running = true
        if (root.showDetails) root.loadDetails()
    }

    function connectTo(name, password) {
        root.status = "Connecting to " + name + "..."
        let cmd = ["nmcli", "dev", "wifi", "connect", name]
        if (password !== "") cmd = cmd.concat(["password", password])
        connectProc.command = cmd
        connectProc.running = true
    }

    function loadDetails() {
        if (!infoProc.running) infoProc.running = true
        if (!ipProc.running) ipProc.running = true
    }

    // ACTIVE,SSID,BSSID,CHAN,FREQ,RATE,SIGNAL,SECURITY
    function parseInfo(output) {
        for (let line of output.trim().split("\n")) {
            let p = line.replace(/\\:/g, "\u0001").split(":")
            if (p[0] !== "yes" || p.length < 8) continue
            let mhz = parseInt(p[4])
            root.info = {
                bssid: p[2].replace(/\u0001/g, ":"),
                channel: p[3],
                band: mhz >= 5925 ? "6 GHz" : mhz >= 4900 ? "5 GHz" : "2.4 GHz",
                rate: p[5],
                security: p[7] === "" ? "Open" : p[7]
            }
            return
        }
    }

    // Reads `nmcli -t -f GENERAL,IP4 dev show` and keeps the wifi device's block
    function parseIp(output) {
        let blocks = []
        let cur = null
        for (let line of output.split("\n")) {
            let i = line.indexOf(":")
            if (i < 0) continue
            let key = line.slice(0, i)
            let val = line.slice(i + 1)
            if (key === "GENERAL.DEVICE") {
                cur = { dns: [] }
                blocks.push(cur)
            }
            if (!cur) continue
            if (key.startsWith("IP4.DNS")) cur.dns.push(val)
            else cur[key] = val
        }
        for (let b of blocks) {
            if (b["GENERAL.TYPE"] === "wifi") {
                root.ipInfo = {
                    device: b["GENERAL.DEVICE"],
                    connection: b["GENERAL.CONNECTION"],
                    address: b["IP4.ADDRESS[1]"],
                    gateway: b["IP4.GATEWAY"],
                    dns: b.dns.join(", ")
                }
                return
            }
        }
    }

    function runAction(action) {
        let name = root.ipInfo.connection || root.ssid
        actionProc.command = ["nmcli", "connection", action, "id", name]
        actionProc.running = true
    }

    // ---------- Processes ----------
    Process {
        id: wifiProc
        command: ["nmcli", "-t", "-f", "ACTIVE,SIGNAL,SECURITY,SSID", "dev", "wifi", "list"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    Process {
        id: radioState
        command: ["nmcli", "radio", "wifi"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.wifiOn = text.trim() === "enabled"
        }
    }

    Process {
        id: radioSet
        onExited: {
            radioState.running = true
            afterToggle.restart()
        }
    }

    Process {
        id: rescanProc
        command: ["nmcli", "dev", "wifi", "rescan"]
        onExited: root.scan()
    }

    Process {
        id: connectProc
        onExited: (exitCode, exitStatus) => {
            root.status = exitCode === 0 ? "Connected" : "Failed to connect"
            root.selectedSsid = ""
            root.scan()
        }
    }

    Process {
        id: infoProc
        command: ["nmcli", "-t", "-f", "ACTIVE,SSID,BSSID,CHAN,FREQ,RATE,SIGNAL,SECURITY", "dev", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: root.parseInfo(text)
        }
    }

    Process {
        id: ipProc
        command: ["nmcli", "-t", "-f", "GENERAL,IP4", "dev", "show"]
        stdout: StdioCollector {
            onStreamFinished: root.parseIp(text)
        }
    }

    Process {
        id: actionProc
        onExited: {
            root.showDetails = false
            root.scan()
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.scan()
    }

    Timer {
        id: afterToggle
        interval: 1500
        onTriggered: root.scan()
    }

    // ---------- UI ----------
    Rectangle {
        anchors.fill: parent
        color: "#A6161925"
        border.color: "#bb9af7"
        border.width: 2
        radius: 12

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 12

            // ----- Title bar -----
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item { Layout.preferredWidth: 15 }

                Text {
                    text: "Wifi"
                    font.bold: true
                    color: "#bb9af7"
                    font.pixelSize: 15
                    font.letterSpacing: 1
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.preferredWidth: 15
                    Layout.preferredHeight: 15
                    radius: 6
                    color: "#bb9af7"

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: "#161925"
                        font.pixelSize: 13
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.quit()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: "#bb9af7"
                opacity: 0.5
            }

            // ----- Use Wifi -----
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "Use Wifi"
                    font.bold: true
                    color: "#bb9af7"
                    font.pixelSize: 20
                    font.letterSpacing: 1
                    Layout.fillWidth: true
                }

                Text {
                    text: root.wifiOn ? "\uf205" : "\uf204"
                    color: root.wifiOn ? "#bb9af7" : "#AA595959"
                    font.family: "JetBrainsMono Nerd Font Propo"
                    font.pixelSize: 40

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            radioSet.command = ["nmcli", "radio", "wifi", root.wifiOn ? "off" : "on"]
                            radioSet.running = true
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: "#bb9af7"
                opacity: 0.5
            }

            // ----- Connected network card (click to expand) -----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: cardCol.implicitHeight + 28
                color: "#A6161925"
                border.color: cardHover.containsMouse || root.expanded ? "#bb9af7" : "#AA595959"
                border.width: 2
                radius: 12
                clip: true

                ColumnLayout {
                    id: cardCol
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 14
                    }
                    spacing: 10

                    // header (always visible)
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42

                        MouseArea {
                            id: cardHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!root.connected) return
                                root.showDetails = !root.showDetails
                                if (root.showDetails) root.loadDetails()
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            spacing: 12

                            Text {
                                text: "\uf1eb"
                                color: "#bb9af7"
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: 26
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: root.connected ? root.ssid : "Not connected"
                                    color: "#bb9af7"
                                    font.bold: true
                                    font.pixelSize: 16
                                }
                                Text {
                                    text: root.connected ? "Connected" : "No Wi-Fi connection"
                                    color: "#bb9af7"
                                    font.pixelSize: 12
                                }
                            }

                            Text {
                                visible: root.connected
                                text: root.strength + "%"
                                color: "#bb9af7"
                                font.pixelSize: 15
                            }

                            Text {
                                text: root.expanded ? "\uf078" : "\uf054"   // down / right chevron
                                color: "#bb9af7"
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: 14
                            }
                        }
                    }

                    // divider
                    Rectangle {
                        visible: root.expanded
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: "#bb9af7"
                        opacity: 0.3
                    }

                    // detail rows
                    ColumnLayout {
                        visible: root.expanded
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: [
                                { k: "Security",   v: root.info.security },
                                { k: "Band",       v: root.info.band },
                                { k: "Channel",    v: root.info.channel },
                                { k: "Link speed", v: root.info.rate },
                                { k: "Signal",     v: root.strength + "%" },
                                { k: "IP address", v: root.ipInfo.address },
                                { k: "Gateway",    v: root.ipInfo.gateway },
                                { k: "DNS",        v: root.ipInfo.dns },
                                { k: "Interface",  v: root.ipInfo.device },
                                { k: "BSSID",      v: root.info.bssid }
                            ]

                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true

                                Text {
                                    text: modelData.k
                                    color: "#AA595959"
                                    font.pixelSize: 13
                                    Layout.preferredWidth: 90
                                }
                                Text {
                                    text: modelData.v || "—"
                                    color: "white"
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // action buttons
                    RowLayout {
                        visible: root.expanded
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: [
                                { label: "Disconnect", action: "down" },
                                { label: "Forget",     action: "delete" }
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                radius: 8
                                color: btnArea.containsMouse ? "#40bb9af7" : "#20ffffff"
                                border.width: 1
                                border.color: "#bb9af7"

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: "#bb9af7"
                                    font.pixelSize: 13
                                }

                                MouseArea {
                                    id: btnArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runAction(modelData.action)
                                }
                            }
                        }
                    }
                }
            }

            // ----- Networks heading + refresh -----
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Networks"
                    font.bold: true
                    color: "#bb9af7"
                    font.pixelSize: 16
                    Layout.fillWidth: true
                }

                Text {
                    text: "\uf021"
                    color: "#bb9af7"
                    opacity: wifiProc.running || rescanProc.running ? 0.4 : 1
                    font.family: "JetBrainsMono Nerd Font Propo"
                    font.pixelSize: 16

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: rescanProc.running = true
                    }
                }
            }

            // ----- Network list -----
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6
                clip: true
                model: root.networks
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 4
                        radius: 2
                        color: "#bb9af7"
                        opacity: 0.6
                    }
                }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool selected: root.selectedSsid === modelData.ssid

                    width: ListView.view.width - 10
                    height: content.implicitHeight + 24
                    radius: 10
                    color: "#A6161925"
                    border.width: 2
                    border.color: rowHover.containsMouse || selected ? "#bb9af7" : "#AA595959"

                    // declared first so the password field sits above it
                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (row.modelData.secure)
                                root.selectedSsid = row.selected ? "" : row.modelData.ssid
                            else
                                root.connectTo(row.modelData.ssid, "")
                        }
                    }

                    ColumnLayout {
                        id: content
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            opacity: row.modelData.strength < 30 ? 0.5 : 1

                            Text {
                                text: "\uf1eb"
                                color: "#bb9af7"
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: 18
                            }
                            Text {
                                text: row.modelData.ssid
                                color: "#bb9af7"
                                font.pixelSize: 15
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: row.modelData.strength + "%"
                                color: "#bb9af7"
                                font.pixelSize: 12
                            }
                            Text {
                                visible: row.modelData.secure
                                text: "\uf023"
                                color: "#bb9af7"
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: 14
                            }
                        }

                        // password box, only for the selected secure network
                        Rectangle {
                            visible: row.selected
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: 8
                            color: "#40000000"
                            border.width: 1
                            border.color: "#AA595959"

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                text: "Password (Enter to connect)"
                                color: "#bb9af7"
                                font.pixelSize: 12
                                visible: pwInput.text === ""
                            }

                            TextInput {
                                id: pwInput
                                anchors.fill: parent
                                anchors.margins: 8
                                color: "white"
                                font.pixelSize: 14
                                echoMode: TextInput.Password
                                clip: true
                                verticalAlignment: TextInput.AlignVCenter
                                onVisibleChanged: if (visible) forceActiveFocus()
                                onAccepted: {
                                    root.connectTo(row.modelData.ssid, text)
                                    text = ""
                                }
                            }
                        }
                    }
                }
            }

            // ----- Status message -----
            Text {
                visible: root.status !== ""
                text: root.status
                color: "#bb9af7"
                font.pixelSize: 12
                Layout.fillWidth: true
            }
        }
    }
}