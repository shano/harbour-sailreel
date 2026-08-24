import QtQuick 2.0
import Sailfish.Silica 1.0
import harbour.sailpipe.extractor 1.0
import "../components"

Page {
    id: settingsPage

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        VerticalScrollDecorator {}

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                //% "Settings"
                title: qsTrId("sailpipe_settings-title")
            }

            SectionHeader {
                //% "yt-dlp (YouTube backend)"
                text: qsTrId("sailpipe_settings-section_ytdlp")
            }

            Label {
                //% "YouTube extraction and downloads use yt-dlp, a separate open-source tool that needs to be installed and kept up to date on this device."
                text: qsTrId("sailpipe_settings-ytdlp_description")
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
                anchors {
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin
                    left: parent.left
                    right: parent.right
                }
            }

            InfoRow {
                //% "Status"
                label: qsTrId("sailpipe_settings-ytdlp_status")
                value: {
                    switch (YtDlp.status) {
                    case YtDlp.NotInstalled:
                        //% "Not installed"
                        return qsTrId("sailpipe_settings-ytdlp_status_not_installed");
                    case YtDlp.Installed:
                        //% "Installed"
                        return qsTrId("sailpipe_settings-ytdlp_status_installed");
                    case YtDlp.CheckingForUpdate:
                        //% "Checking for updates…"
                        return qsTrId("sailpipe_settings-ytdlp_status_checking");
                    case YtDlp.Downloading:
                        //% "Downloading…"
                        return qsTrId("sailpipe_settings-ytdlp_status_downloading");
                    default:
                        //% "Error"
                        return qsTrId("sailpipe_settings-ytdlp_status_error");
                    }
                }
            }

            InfoRow {
                //% "Installed version"
                label: qsTrId("sailpipe_settings-ytdlp_installed_version")
                value: YtDlp.installedVersion.length > 0 ? YtDlp.installedVersion : "—"
            }

            InfoRow {
                //% "Latest version"
                label: qsTrId("sailpipe_settings-ytdlp_latest_version")
                value: YtDlp.latestVersion.length > 0 ? YtDlp.latestVersion : "—"
            }

            ProgressBar {
                width: parent.width
                x: Theme.horizontalPageMargin
                visible: YtDlp.status === YtDlp.Downloading
                value: YtDlp.progress
                minimumValue: 0.0
                maximumValue: 1.0
            }

            Row {
                spacing: Theme.paddingLarge
                anchors.horizontalCenter: parent.horizontalCenter

                Button {
                    //% "Check for Updates"
                    text: qsTrId("sailpipe_settings-ytdlp_check_updates")
                    enabled: YtDlp.status !== YtDlp.Downloading && YtDlp.status !== YtDlp.CheckingForUpdate
                    onClicked: YtDlp.checkForUpdate()
                }

                Button {
                    text: {
                        if (YtDlp.status === YtDlp.NotInstalled) {
                            //% "Install"
                            return qsTrId("sailpipe_settings-ytdlp_install");
                        }
                        //% "Update"
                        return qsTrId("sailpipe_settings-ytdlp_update");
                    }
                    enabled: YtDlp.status !== YtDlp.Downloading
                    onClicked: {
                        if (YtDlp.status === YtDlp.NotInstalled) {
                            YtDlp.install();
                        } else {
                            YtDlp.update();
                        }
                    }
                }
            }

            SectionHeader {
                //% "SponsorBlock"
                text: qsTrId("sailpipe_settings-section_sponsorblock")
            }

            Label {
                //% "Removes sponsor, self-promo, and \"like/subscribe\" segments from downloaded videos, and skips them automatically during in-app playback, using the community-maintained SponsorBlock database."
                text: qsTrId("sailpipe_settings-sponsorblock_description")
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
                anchors {
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin
                    left: parent.left
                    right: parent.right
                }
            }

            TextSwitch {
                //% "Remove sponsor segments"
                text: qsTrId("sailpipe_settings-sponsorblock_toggle")
                checked: YtDlp.sponsorBlockEnabled
                onCheckedChanged: {
                    YtDlp.sponsorBlockEnabled = checked;
                }
            }

            SectionHeader {
                //% "Diagnostics"
                text: qsTrId("sailpipe_settings-section_diagnostics")
            }

            Label {
                //% "Copy this device's debug log to the clipboard, e.g. to include when reporting a playback or extraction problem."
                text: qsTrId("sailpipe_settings-diagnostics_description")
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
                anchors {
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin
                    left: parent.left
                    right: parent.right
                }
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                //% "Copy Debug Log"
                text: qsTrId("sailpipe_settings-diagnostics_copy_log")
                onClicked: {
                    if (YtDlp.copyDebugLogToClipboard()) {
                        //% "Debug log copied to clipboard"
                        banner.text = qsTrId("sailpipe_settings-diagnostics_copied");
                    } else {
                        //% "No debug log found on this device"
                        banner.text = qsTrId("sailpipe_settings-diagnostics_empty");
                    }
                    banner.show();
                }
            }

            Connections {
                target: YtDlp
                onErrorOccurred: {
                    //% "yt-dlp error: %1"
                    banner.text = qsTrId("sailpipe_settings-ytdlp_error").arg(message);
                    banner.show();
                }
            }

            Label {
                id: banner
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.errorColor
                visible: text.length > 0
                function show() { visible = true; }
                anchors {
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin
                    left: parent.left
                    right: parent.right
                }
            }
        }
    }
}
