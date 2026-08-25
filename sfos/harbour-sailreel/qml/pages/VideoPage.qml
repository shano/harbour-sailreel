import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Share 1.0
import harbour.sailpipe.extractor 1.0
import "../components"

Page {
    id: root
    property string name
    property string thumbnail
    property string url
    property MediaInfo mediaInfo: MediaInfo { id: mediaInfo }
    property alias source: mediaInfo.content
    property string errorMessage
    property bool commentsLoadTriggered: false

    // Comments load after the video extraction is known to have finished
    // (success or failure) rather than alongside it — both go through the
    // same yt-dlp subprocess pool, and comments (--write-comments, up to a
    // 60s timeout) competing with the video's own extraction for CPU and
    // network was a plausible contributor to slow/stalled video loads.
    function loadCommentsOnce() {
        if (!commentsLoadTriggered) {
            commentsLoadTriggered = true;
            comments.model.loadComments(extractor, url);
        }
    }

    onSourceChanged: loadCommentsOnce()
    onErrorMessageChanged: loadCommentsOnce()

    Component.onCompleted: {
        extractor.downloadExtract(mediaInfo, url);
        DownloadManager.page = url;
        DownloadManager.name = name;
        MediaJunction.controllable = false;
    }

    Component.onDestruction: {
        MediaJunction.controllable = false;
    }

    Connections {
        target: extractor
        onErrorOccurred: {
            root.errorMessage = message;
        }
    }

    SilicaListView {
        id: comments
        model: CommentModel {}
        anchors.fill: parent

        VerticalScrollDecorator {}

        onContentYChanged: {
            var pos = contentHeight + originY - height - contentY;
            if ((pos < height) && !comments.model.loading && comments.model.more && comments.model.nextPage) {
                comments.model.loadComments(extractor, url);
            }
        }

        header: Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                id: header
                //% "YouTube Video"
                title: qsTrId("sailpipe_media-page_header_video")
            }

            Connections {
                target: root

                onStatusChanged: {
                    if (status === PageStatus.Active) {
                        video.state = "hidden"
                        video.parent = video.oldparent;
                        video.state = ""
                    }
                }
            }

            Item {
                width: parent.width
                height: width * (9 / 16)

                VideoPlayer {
                    id: video
                    width: parent.width
                    height: parent.height
                    source: root.source
                    thumbnail: root.thumbnail
                    name: root.name
                    uploader: root.mediaInfo.uploaderName
                    videoUrl: root.url
                    hasError: root.errorMessage.length > 0

                    onPlaybackError: {
                        root.errorMessage = message;
                    }
                }
            }

            ActionBar {
                x: Theme.paddingLarge
                width: parent.width - (2 * Theme.paddingLarge)
                downloadable: (root.source != "")

                onFullscreenPressed: {
                    video.state = "hidden"
                }

                onSharePressed: {
                    shareAction.resources = [{ "type": "text/x-url", "status": root.url.toString() }];
                    shareAction.trigger();
                }

                onDownloadPressed: {
                    DownloadManager.downloadFile(root.source);
                }

                onDownloadCancelPressed: {
                    DownloadManager.cancel();
                }

                onOpenPagePressed: {
                    Qt.openUrlExternally(url)
                }

                ShareAction {
                    id: shareAction
                    mimeType: "text/x-url"
                }
            }

            Label {
                id: videoTitle
                x: Theme.paddingLarge
                width: parent.width - (2 * Theme.paddingLarge)
                color: Theme.highlightColor
                wrapMode: Text.Wrap
                text: root.name
            }

            Label {
                id: uploaderLabel
                x: Theme.paddingLarge
                width: parent.width - (2 * Theme.paddingLarge)
                color: uploaderMouseArea.pressed ? Theme.highlightColor : Theme.secondaryHighlightColor
                truncationMode: TruncationMode.Fade
                text: root.mediaInfo.uploaderName
                visible: text.length > 0

                MouseArea {
                    id: uploaderMouseArea
                    anchors.fill: parent
                    enabled: root.mediaInfo.uploaderUrl.length > 0
                    onClicked: {
                        pageStack.push(Qt.resolvedUrl("ChannelPage.qml"), {
                            name: root.mediaInfo.uploaderName,
                            url: root.mediaInfo.uploaderUrl
                        });
                    }
                }
            }

            MediaDetails {
                mediaInfo: root.mediaInfo
            }
        }

        delegate: CommentItem {
            url: root.url
            uploaderAvatar: model.uploaderAvatar
            uploaderName: model.uploaderName
            commentText: model.commentText
            replyCount: model.replyCount
            page: model.page
        }

        ProcessIndicator {
            loading: comments.model.loading
            count: comments.count
            //% "No comments"
            text: qsTrId("sailpipe_comments-no_entries")
            //% "There are no comments here"
            hintText: qsTrId("sailpipe_comments-no_entries_hint")
        }
    }

    Label {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: Theme.horizontalPageMargin
            rightMargin: Theme.horizontalPageMargin
            bottomMargin: Theme.paddingLarge
        }
        text: root.errorMessage
        visible: text.length > 0
        wrapMode: Text.WordWrap
        color: Theme.highlightColor
        horizontalAlignment: Text.AlignHCenter
    }
}

