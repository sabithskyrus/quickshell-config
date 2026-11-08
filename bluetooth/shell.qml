import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

PanelWindow {
    id: root
    implicitWidth: 450
    implicitHeight: 600
    color: "transparent"

    // ---------- State ----------
    property bool hasAdapter: true
    property bool powered: false
    property bool scanning: false
    property var devices: []
    property string lastJson: ""
    property string expandedMac: ""
    property string status: ""

    // ---------- Logic ----------
    // Reads `bluetoothctl show`
    function parseShow(output) {
        root.hasAdapter = output.indexOf("Controller") >= 0
        root.powered = output.indexOf("Powered: yes") >= 0
    }

    // Reads the combined `bluetoothctl info` output of every known device
    function parseDevices(output) {
        let list = []
        let cur = null

        for (let raw of output.split("\n")) {
            let line = raw.trim()

            if (line.startsWith("Device ")) {
                let p = line.split(" ")
                if (line.indexOf("not available") >= 0) { cur = null; continue }
                cur = {
                    address: p[1],
                    name: p[1],
                    icon: "",
                    paired: false,
                    connected: false,
                    trusted: false,
                    battery: -1
                }
                list.push(cur)
                continue
            }
            if (!cur) continue

            let i = line.indexOf(":")
            if (i < 0) continue
            let k = line.slice(0, i)
            let v = line.slice(i + 1).trim()

            if (k === "Alias") cur.name = v
            else if (k === "Icon") cur.icon = v
            else if (k === "Paired") cur.paired = v === "yes"
            else if (k === "Connected") cur.connected = v === "yes"
            else if (k === "Trusted") cur.trusted = v === "yes"
            else if (k === "Battery Percentage") {
                let m = v.match(/\((\d+)\)/)
                if (m) cur.battery = parseInt(m[1])
            }
        }

        for (let d of list)
            d.group = (d.paired || d.connected) ? "My devices" : "Available"

        // my devices first, connected ones on top, then by name
        list.sort((a, b) => {
            if (a.group !== b.group) return a.group === "My devices" ? -1 : 1
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            return a.name.localeCompare(b.name)
        })

        // only replace the model when something changed, so the list doesn't flicker
        let json = JSON.stringify(list)
        if (json !== root.lastJson) {
            root.lastJson = json
            root.devices = list
        }
    }

    function refresh() {
        if (!showProc.running) showProc.running = true
        if (!devicesProc.running) devicesProc.running = true
    }

    function run(cmd, label) {
        if (actionProc.running) return
        root.status = label + "..."
        actionProc.command = cmd
        actionProc.running = true
    }

    function glyph(icon) {
        if (icon.indexOf("headphone") >= 0 || icon.indexOf("headset") >= 0) return "\uf025"
        if (icon.indexOf("audio") >= 0) return "\uf028"
        if (icon.indexOf("keyboard") >= 0) return "\uf11c"
        if (icon.indexOf("mouse") >= 0) return "\uf245"
        if (icon.indexOf("gaming") >= 0) return "\uf11b"
        if (icon.indexOf("phone") >= 0) return "\uf10b"
        if (icon.indexOf("computer") >= 0) return "\uf108"
        return "\uf294"
    }

    // ---------- Processes ----------
    Process {
        id: showProc
        command: ["bluetoothctl", "show"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.parseShow(text)
        }
    }

    Process {
        id: devicesProc
        command: ["sh", "-c", "for m in $(bluetoothctl devices | awk '{print $2}'); do bluetoothctl info \"$m\"; done"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.parseDevices(text)
        }
    }

    Process {
        id: powerProc
        onExited: {
            root.refresh()
            afterPower.restart()
        }
    }

    Process {
        id: scanProc
        command: ["bluetoothctl", "--timeout", "8", "scan", "on"]
        onRunningChanged: {
            root.scanning = running
            if (!running) root.refresh()
        }
    }

    Process {
        id: actionProc
        onExited: (exitCode, exitStatus) => {
            root.status = exitCode === 0 ? "Done" : "Failed"
            root.refresh()
        }
    }

    Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: afterPower
        interval: 1500
        onTriggered: root.refresh()
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
                    text: "Bluetooth"
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

            // ----- Use Bluetooth -----
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "Use Bluetooth"
                    font.bold: true
                    color: "#bb9af7"
                    font.pixelSize: 20
                    font.letterSpacing: 1
                    Layout.fillWidth: true
                }

                Text {
                    text: root.powered ? "\uf205" : "\uf204"
                    color: root.powered ? "#bb9af7" : "#AA595959"
                    font.family: "JetBrainsMono Nerd Font Propo"
                    font.pixelSize: 40

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.hasAdapter) return
                            powerProc.command = ["bluetoothctl", "power", root.powered ? "off" : "on"]
                            powerProc.running = true
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

            // ----- Devices heading + scan button -----
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Devices"
                    font.bold: true
                    color: "#bb9af7"
                    font.pixelSize: 16
                    Layout.fillWidth: true
                }

                Text {
                    visible: root.scanning
                    text: "Scanning..."
                    color: "#bb9af7"
                    font.pixelSize: 12
                }

                Text {
                    text: "\uf021"
                    color: "#bb9af7"
                    opacity: root.scanning || !root.powered ? 0.4 : 1
                    font.family: "JetBrainsMono Nerd Font Propo"
                    font.pixelSize: 16

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.powered && !scanProc.running) scanProc.running = true
                        }
                    }
                }
            }

            // ----- Device list -----
            ListView {
                visible: root.powered
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8
                clip: true
                model: root.devices
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    width: 6
                    contentItem: Rectangle {
                        implicitWidth: 4
                        radius: 2
                        color: "#bb9af7"
                        opacity: 0.6
                    }
                }

                delegate: Item {
                    id: item
                    required property var modelData
                    required property int index

                    readonly property var dev: modelData
                    readonly property bool expanded: root.expandedMac === dev.address
                    readonly property bool showHeader: index === 0 || root.devices[index - 1].group !== dev.group

                    width: ListView.view.width - 10
                    height: col.implicitHeight

                    function makeButtons() {
                        let mac = dev.address
                        let b = []
                        if (dev.connected)
                            b.push({ label: "Disconnect", status: "Disconnecting",
                                     cmd: ["bluetoothctl", "disconnect", mac] })
                        else if (dev.paired)
                            b.push({ label: "Connect", status: "Connecting",
                                     cmd: ["bluetoothctl", "connect", mac] })
                        else
                            b.push({ label: "Pair and connect", status: "Pairing",
                                     cmd: ["sh", "-c",
                                           "bluetoothctl pair $0 && bluetoothctl trust $0 && bluetoothctl connect $0", mac] })
                        if (dev.paired)
                            b.push({ label: "Forget", status: "Removing",
                                     cmd: ["bluetoothctl", "remove", mac] })
                        return b
                    }

                    ColumnLayout {
                        id: col
                        width: parent.width
                        spacing: 6

                        // section heading
                        Text {
                            visible: item.showHeader
                            text: item.dev.group
                            color: "#bb9af7"
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 1
                        }

                        // device card
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: cardCol.implicitHeight + 24
                            radius: 10
                            color: "#A6161925"
                            border.width: 1
                            border.color: hover.containsMouse || item.expanded || item.dev.connected
                                          ? "#bb9af7" : "transparent"
                            clip: true

                            ColumnLayout {
                                id: cardCol
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                    margins: 12
                                }
                                spacing: 10

                                // header (always visible)
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 34

                                    MouseArea {
                                        id: hover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.expandedMac = item.expanded ? "" : item.dev.address
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 12

                                        Text {
                                            text: root.glyph(item.dev.icon)
                                            color: "#bb9af7"
                                            font.family: "JetBrainsMono Nerd Font Propo"
                                            font.pixelSize: 20
                                            Layout.preferredWidth: 24
                                            horizontalAlignment: Text.AlignHCenter
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            Text {
                                                text: item.dev.name
                                                color: "#bb9af7"
                                                font.pixelSize: 15
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: item.dev.connected ? "Connected"
                                                      : item.dev.paired ? "Paired" : "Available"
                                                color: item.dev.connected ? "#bb9af7" : "#bb9af7"
                                                font.pixelSize: 12
                                            }
                                        }

                                        Text {
                                            visible: item.dev.battery >= 0
                                            text: item.dev.battery + "%"
                                            color: "#bb9af7"
                                            font.pixelSize: 13
                                        }

                                        Text {
                                            text: item.expanded ? "\uf078" : "\uf054"
                                            color: "#bb9af7"
                                            font.family: "JetBrainsMono Nerd Font Propo"
                                            font.pixelSize: 14
                                        }
                                    }
                                }

                                // divider
                                Rectangle {
                                    visible: item.expanded
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: "#A6161925"
                                    opacity: 0.3
                                }

                                // detail rows
                                ColumnLayout {
                                    visible: item.expanded
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Repeater {
                                        model: [
                                            { k: "Address", v: item.dev.address },
                                            { k: "Type",    v: item.dev.icon || "unknown" },
                                            { k: "Paired",  v: item.dev.paired ? "Yes" : "No" },
                                            { k: "Trusted", v: item.dev.trusted ? "Yes" : "No" },
                                            { k: "Battery", v: item.dev.battery >= 0 ? item.dev.battery + "%" : "" }
                                        ]

                                        delegate: RowLayout {
                                            required property var modelData
                                            Layout.fillWidth: true

                                            Text {
                                                text: modelData.k
                                                color: "#bb9af7"
                                                font.pixelSize: 13
                                                Layout.preferredWidth: 80
                                            }
                                            Text {
                                                text: modelData.v || "—"
                                                color: "#bb9af7"
                                                font.pixelSize: 13
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }
                                }

                                // action buttons
                                RowLayout {
                                    visible: item.expanded
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Repeater {
                                        model: item.makeButtons()

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
                                                onClicked: root.run(modelData.cmd, modelData.status)
                                            }
                                        }
                                    }
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