import QtQuick 2.0
import Sailfish.Silica 1.0
import QtMultimedia 5.0
import harbour.sailpipe.extractor 1.0

Item {
    id: root
    property var oldparent: parent

    property alias source: media.source
    property alias thumbnail: image.source
    property string name
    property string uploader
    property string videoUrl
    property bool controlsvisible: false
    property int skipTimeShort: 10
    property int skipTimeLong: 60
    property bool resumed: false
    property var sponsorSegments: []
    property bool hasError: false

    onVideoUrlChanged: {
        sponsorSegments = [];
        if (YtDlp.sponsorBlockEnabled && (videoUrl.length > 0)) {
            SponsorBlock.fetchSegments(videoUrl);
        }
    }

    Connections {
        target: SponsorBlock
        onSegmentsReady: {
            if (videoUrl === root.videoUrl) {
                root.sponsorSegments = segments;
            }
        }
    }

    function skipSponsorSegment(positionMs) {
        for (var i = 0; i < sponsorSegments.length; i++) {
            var segment = sponsorSegments[i];
            if ((positionMs >= segment.startMs) && (positionMs < segment.endMs - 250)) {
                media.seek(segment.endMs);
                mediaslider.value = segment.endMs;
                return;
            }
        }
    }

    readonly property int controlgap: 2 * Theme.paddingLarge
    readonly property bool playing: (media.playbackState == MediaPlayer.PlayingState)
    property bool controllable: isControllable()
    property bool forceVisible: controllable
    readonly property bool portrait: video.sourceRect.width < video.sourceRect.height

    function playPause() {
        if (forceVisible) {
            forceVisible = false;
            closeControls();
        }
        else {
            openControls()
        }
        if (playing) {
            media.pause()
        }
        else {
            media.play()
        }
    }

    function reverse() {
        openControls()
        media.seek(media.position - (1000 * skipTimeShort))
        mediaslider.value = mediaslider.value - (1000 * skipTimeShort)
    }

    function reverseLong() {
        openControls()
        media.seek(media.position - (1000 * skipTimeLong))
        mediaslider.value = mediaslider.value - (1000 * skipTimeLong)
    }

    function forwards() {
        openControls()
        media.seek(media.position + (1000 * skipTimeShort))
        mediaslider.value = mediaslider.value + (1000 * skipTimeShort)
    }

    function forwardsLong() {
        openControls()
        media.seek(media.position + (1000 * skipTimeLong))
        mediaslider.value = mediaslider.value + (1000 * skipTimeLong)
    }

    onPortraitChanged: {
        if (portrait) {
            if (state == "fullscreenLandscape") {
                state = "fullscreenPortrait";
            }
        }
        else {
            if (state == "fullscreenPortrait") {
                state = "fullscreenLandscape";
            }
        }
    }

    width: parent.width
    height: width * (9 / 16)

    function isControllable() {
        var result = true;
        switch (media.status) {
        case MediaPlayer.NoMedia:
        case MediaPlayer.Loading:
        case MediaPlayer.InvalidMedia:
        case MediaPlayer.UnknownStatus:
            result = false;
        }
        return result;
    }

    onForceVisibleChanged: {
        if ((forceVisible == true) && (controllable == true)) {
            openControls();
        }
    }

    function toggleControls() {
        if ((!controlsvisible) || (fadeout.running)) {
            fadeout.stop()
            controls.opacity = 1
            controlsvisible = true
            controlsTimer.restart()
        }
        else {
            controlsTimer.stop()
            fadeout.stop()
            controlsvisible = false
        }
    }

    function openControls () {
        fadeout.stop()
        controls.opacity = 1
        controlsvisible = true
        if (forceVisible) {
            controlsTimer.stop()
        }
        else {
            controlsTimer.restart()
        }
    }

    function closeControls () {
        controlsTimer.stop()
        fadeout.stop()
        controlsvisible = false
    }

    signal playbackError(string message)

    MediaPlayer {
        id: media
        autoPlay: false
        autoLoad: true
        onPositionChanged: {
            mediaslider.value = position
            root.skipSponsorSegment(position)
        }
        onDurationChanged: {
            if (!root.resumed && (duration > 0) && (root.videoUrl.length > 0)) {
                root.resumed = true;
                var resumeMs = WatchHistory.positionMs(root.videoUrl);
                if ((resumeMs > 3000) && (resumeMs < duration * 0.95)) {
                    seek(resumeMs);
                    mediaslider.value = resumeMs;
                }
            }
        }
        onStatusChanged: {
            if (status == MediaPlayer.EndOfMedia) {
                seek(0);
                forceVisible = true;
                openControls();
            }
            // MediaPlayer.error's own signal doesn't always fire for a
            // stream URL that fails to load at all (as opposed to failing
            // mid-playback) — InvalidMedia here is the only reliable signal
            // that the resolved yt-dlp URL genuinely couldn't be played.
            if (status == MediaPlayer.InvalidMedia) {
                Utils.logDebug("VideoPlayer: InvalidMedia for source=" + media.source + " errorString=" + media.errorString);
                //% "This video could not be played"
                root.playbackError(media.errorString.length > 0 ? media.errorString : qsTrId("sailpipe_video_player-playback_error"));
            }
            // Some resolved stream URLs (observed with YouTube's SABR
            // rotation) never fail outright — gstreamer just sits in
            // Loading forever instead of reaching Buffering/Buffered or
            // erroring, so InvalidMedia/onError above never fire either.
            if (status == MediaPlayer.Loading) {
                loadStallTimer.restart();
            }
            else {
                loadStallTimer.stop();
            }
        }
        onError: {
            Utils.logDebug("VideoPlayer: MediaPlayer error=" + error + " errorString=" + errorString);
            //% "This video could not be played"
            root.playbackError(errorString.length > 0 ? errorString : qsTrId("sailpipe_video_player-playback_error"));
        }
    }

    Binding {
        target: MediaJunction
        property: "playing"
        value: playing
    }
    Binding {
        target: MediaJunction
        property: "position"
        value: media.position
    }
    Binding {
        target: MediaJunction
        property: "duration"
        value: media.duration
    }
    Binding {
        target: MediaJunction
        property: "title"
        value: root.name
    }
    Binding {
        target: MediaJunction
        property: "creator"
        value: root.uploader
    }
    Binding {
        target: MediaJunction
        property: "controllable"
        value: controllable
    }
    Binding {
        target: MediaJunction
        property: "thumbnail"
        value: root.thumbnail
    }

    Connections {
        target: MediaJunction
        onPlayPauseRequested: playPause()
        onSkipBackwardsRequested: reverse()
        onSkipForwardsRequested: forwards()
    }

    VideoOutput {
        id: video
        anchors.fill: parent
        width: parent.width
        height: width * (9 / 16)
        fillMode: Image.PreserveAspectFit
        source: media

        Image {
            id: image
            anchors.fill: parent
            fillMode: Image.PreserveAspectFit
            visible: !controllable || forceVisible || !media.hasVideo
        }
    }

    Timer {
        id: progressSaveTimer
        interval: 5000
        running: playing
        repeat: true
        onTriggered: {
            if ((root.videoUrl.length > 0) && (media.duration > 0)) {
                WatchHistory.setProgress(root.videoUrl, media.position, media.duration);
            }
        }
    }

    Component.onDestruction: {
        if ((root.videoUrl.length > 0) && (media.duration > 0) && (media.position > 0)) {
            WatchHistory.setProgress(root.videoUrl, media.position, media.duration);
        }
    }

    Timer {
        id: loadStallTimer
        interval: 20000
        running: false
        repeat: false
        onTriggered: {
            Utils.logDebug("VideoPlayer: load stalled for source=" + media.source);
            //% "This video is taking too long to load"
            root.playbackError(qsTrId("sailpipe_video_player-load_timeout"));
        }
    }

    Timer {
        id: controlsTimer
        interval: 10000
        running: false
        repeat: false
        triggeredOnStart: false
        onTriggered: {
            fadeout.start()
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            toggleControls()
        }
    }

    Item {
        id: controls
        anchors.fill: parent
        visible: (controllable && controlsvisible) || forceVisible
        opacity: 1

        NumberAnimation on opacity {
            id: fadeout
            from: 1
            to: 0
            duration: 1000
            onRunningChanged: {
                if (!running) {
                    controlsvisible = false
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                toggleControls()
            }
        }

        IconButton {
            id: playbutton
            width: Theme.iconSizeLarge
            height: Theme.iconSizeLarge
            icon.sourceSize.width: width
            icon.sourceSize.height: height
            icon.fillMode: Image.PreserveAspectFit
            anchors.verticalCenter: parent.verticalCenter
            anchors.bottomMargin: controlgap
            anchors.horizontalCenter: parent.horizontalCenter
            icon.source: (playing ? Qt.resolvedUrl("image://theme/icon-l-pause?") : Qt.resolvedUrl("image://theme/icon-l-play?"))
                    + (pressed ? Theme.highlightColor : Theme.primaryColor)

            onClicked: playPause()
        }

        IconButtonDual {
            id: reversebutton
            width: Theme.iconSizeLarge
            height: Theme.iconSizeLarge
            anchors.verticalCenter: playbutton.verticalCenter
            anchors.right: playbutton.left
            anchors.rightMargin: controlgap
            visible: media.seekable
            icon.source: Qt.resolvedUrl("image://sailpipe/icon-l-replay?") + (pressed ? Theme.highlightColor : Theme.primaryColor)

            onShortClick: reverse()
            onLongClick: reverseLong()
        }

        IconButtonDual {
            id: forwardsbutton
            width: Theme.iconSizeLarge
            height: Theme.iconSizeLarge
            anchors.verticalCenter: playbutton.verticalCenter
            anchors.left: playbutton.right
            anchors.leftMargin: controlgap
            visible: media.seekable
            icon.source: Qt.resolvedUrl("image://sailpipe/icon-l-skip?") + (pressed ? Theme.highlightColor : Theme.primaryColor)

            onShortClick: forwards()
            onLongClick: forwardsLong()
        }

        Slider {
            id: mediaslider
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            visible: media.seekable
            minimumValue: 0
            maximumValue: Math.max(1, media.duration)
            stepSize: 1
            value: 0
            enabled: media.seekable
            valueText: Utils.millisecondsToTime(sliderValue)
            onPressed: {
                openControls()
                controlsTimer.stop()
            }
            onReleased: {
                media.seek(sliderValue)
                openControls()
            }
        }

        IconButton {
            id: fullscreenbutton
            width: Theme.iconSizeMedium
            height: Theme.iconSizeMedium
            icon.sourceSize.width: width
            icon.sourceSize.height: height
            icon.fillMode: Image.PreserveAspectFit
            anchors.right: parent.right
            anchors.rightMargin: Theme.paddingLarge
            anchors.top: parent.top
            anchors.topMargin: Theme.paddingLarge
            icon.source: Qt.resolvedUrl("image://theme/icon-m-dismiss?") + (pressed ? Theme.highlightColor : Theme.primaryColor)
            visible: root.state == "fullscreenLandscape" || root.state == "fullscreenPortrait"

            onClicked: {
                pageStack.pop();
            }
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: true
        visible: !controllable && !hasError
        size: BusyIndicatorSize.Medium
    }

    function finaliseFullscreen(parent) {
        root.state = root.portrait ? "fullscreenPortrait" : "fullscreenLandscape";
        root.oldparent = root.parent
        root.parent = parent;
    }

    states: [
        State {
            name: "hidden"
            PropertyChanges {
                target: root
                opacity: 0.0
            }
        },
        State {
            name: "fullscreenLandscape"
            PropertyChanges {
                target: root
                width: parent.height
                height: parent.width
                rotation: 90
                x: (Screen.width / 2.0) - (Screen.height / 2.0)
                y: (Screen.height / 2.0) - (Screen.width / 2.0)
                opacity: 1.0
            }
        },
        State {
            name: "fullscreenPortrait"
            PropertyChanges {
                target: root
                width: parent.width
                height: parent.height
                rotation: 0
                x: 0
                y: 0
                opacity: 1.0
            }
        }
    ]

    transitions: [
        Transition {
            from: ""; to: "hidden"; reversible: true
            NumberAnimation { properties: "opacity"; duration: 100; easing.type: Easing.InOutQuad }
            onRunningChanged: {
                if ((!running) && (root.state == "hidden")) {
                    root.state = root.portrait ? "fullscreenPortrait" : "fullscreenLandscape";
                    pageStack.push(Qt.resolvedUrl("../pages/FullscreenVideoPage.qml"), {video: root});
                }
            }
        },
        Transition {
            from: "fullscreenLandscape"; to: "fullscreenPortrait"; reversible: true
            NumberAnimation { properties: "rotation,width,height,x,y"; duration: 200; easing.type: Easing.InOutQuad }
        }
    ]
}
