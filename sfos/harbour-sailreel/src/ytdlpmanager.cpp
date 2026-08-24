#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QTextStream>
#include <QSysInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QProcess>
#include <QNetworkRequest>
#include <QSettings>
#include <QUrlQuery>
#include <QCryptographicHash>
#include <QtConcurrent/QtConcurrent>

#include "ytdlpmanager.h"

#define GITHUB_LATEST_RELEASE_URL "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"
#define SPONSORBLOCK_CATEGORIES "sponsor,selfpromo,interaction"

// Sailfish's qDebug() output goes to journald via libsailfishapp's message
// handler, which isn't reliably readable without systemd-journal group
// membership. Mirror install diagnostics to a plain file too so they can be
// read directly regardless of journal permissions.
static void logToFile(QString const& line)
{
  QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
  QDir().mkpath(dataDir);
  QFile logFile(dataDir + QStringLiteral("/debug.log"));
  if (logFile.open(QIODevice::Append | QIODevice::Text)) {
    QTextStream stream(&logFile);
    stream << QDateTime::currentDateTime().toString(Qt::ISODate) << ' ' << line << '\n';
  }
  qDebug() << line;
}

static QString settingsPath()
{
  QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
  return dataDir + QStringLiteral("/settings.ini");
}

YtDlpManager* YtDlpManager::m_instance = nullptr;

YtDlpManager::YtDlpManager(QObject *parent)
  : QObject(parent)
  , m_manager(new QNetworkAccessManager(this))
  , m_activeReply(nullptr)
  , m_status(NotInstalled)
  , m_installedVersion()
  , m_latestVersion()
  , m_progress(0.0)
  , m_threadPool()
  , m_versionWatcher()
  , m_sponsorBlockEnabled(false)
{
  connect(&m_versionWatcher, &QFutureWatcher<QString>::finished, this, &YtDlpManager::onVersionCheckFinished);
  refreshInstalledVersion();

  // Explicit path inside AppDataLocation rather than QSettings' default
  // org/app-derived ~/.config/<org>/<app>.conf — that path isn't confirmed
  // whitelisted by sailjail (see the earlier OrganizationName sandbox
  // write-failure this session), whereas AppDataLocation already is
  // (SubscriptionManager, debug.log, and the yt-dlp binary all write there).
  QSettings settings(settingsPath(), QSettings::IniFormat);
  m_sponsorBlockEnabled = settings.value(QStringLiteral("sponsorBlockEnabled"), false).toBool();
}

void YtDlpManager::instantiate(QObject* parent)
{
  if (m_instance == nullptr) {
    m_instance = new YtDlpManager(parent);
  }
}

YtDlpManager& YtDlpManager::getInstance()
{
  return *m_instance;
}

QObject* YtDlpManager::provider(QQmlEngine* engine, QJSEngine* scriptEngine)
{
  Q_UNUSED(engine)
  Q_UNUSED(scriptEngine)

  return m_instance;
}

QString YtDlpManager::binaryPath()
{
  QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
  return QString("%1/yt-dlp/yt-dlp").arg(dataDir);
}

QString YtDlpManager::releaseAssetName()
{
  // currentCpuArchitecture() reflects the running kernel, which on some
  // devices is 64bit even though the app/userspace is armv7hl (32bit).
  // buildCpuArchitecture() reflects what the app was compiled for, which
  // matches the RPM target/userspace ABI actually in use.
  QString arch = QSysInfo::buildCpuArchitecture();
  if (arch == QLatin1String("arm64")) {
    return QStringLiteral("yt-dlp_linux_aarch64");
  }
  // armv7hl devices report "arm" from QSysInfo; only the zipped asset
  // exists upstream for this architecture. Extraction is handled by the
  // caller (install()) when the asset name ends in .zip.
  return QStringLiteral("yt-dlp_linux_armv7l.zip");
}

YtDlpManager::Status YtDlpManager::status() const
{
  return m_status;
}

QString YtDlpManager::installedVersion() const
{
  return m_installedVersion;
}

QString YtDlpManager::latestVersion() const
{
  return m_latestVersion;
}

float YtDlpManager::progress() const
{
  return m_progress;
}

bool YtDlpManager::sponsorBlockEnabled() const
{
  return m_sponsorBlockEnabled;
}

void YtDlpManager::setSponsorBlockEnabled(bool enabled)
{
  if (m_sponsorBlockEnabled != enabled) {
    m_sponsorBlockEnabled = enabled;
    QSettings settings(settingsPath(), QSettings::IniFormat);
    settings.setValue(QStringLiteral("sponsorBlockEnabled"), enabled);
    emit sponsorBlockEnabledChanged();
  }
}

QString YtDlpManager::sponsorBlockCategories()
{
  return QStringLiteral(SPONSORBLOCK_CATEGORIES);
}

void YtDlpManager::setStatus(Status status)
{
  if (m_status != status) {
    m_status = status;
    emit statusChanged();
  }
}

void YtDlpManager::setInstalledVersion(QString const& version)
{
  if (m_installedVersion != version) {
    m_installedVersion = version;
    emit installedVersionChanged();
  }
}

void YtDlpManager::setLatestVersion(QString const& version)
{
  if (m_latestVersion != version) {
    m_latestVersion = version;
    emit latestVersionChanged();
  }
}

void YtDlpManager::setProgress(float progress)
{
  if (m_progress != progress) {
    m_progress = progress;
    emit progressChanged();
  }
}

void YtDlpManager::refreshInstalledVersion()
{
  QFileInfo info(binaryPath());
  if (!info.exists() || !info.isExecutable()) {
    setInstalledVersion(QString());
    setStatus(NotInstalled);
    return;
  }

  QFuture<QString> future = QtConcurrent::run(&m_threadPool, [this]() {
    return getInstalledVersion();
  });
  m_versionWatcher.setFuture(future);
}

void YtDlpManager::checkForUpdate()
{
  if (m_status == CheckingForUpdate || m_status == Downloading) {
    return;
  }

  setStatus(CheckingForUpdate);

  QNetworkRequest request{QUrl(QStringLiteral(GITHUB_LATEST_RELEASE_URL))};
  request.setRawHeader("Accept", "application/vnd.github+json");
  request.setRawHeader("User-Agent", "harbour-sailreel");

  m_activeReply = m_manager->get(request);
  connect(m_activeReply, &QNetworkReply::finished, this, &YtDlpManager::onLatestReleaseReply);
}

void YtDlpManager::onLatestReleaseReply()
{
  QNetworkReply* reply = m_activeReply;
  m_activeReply = nullptr;

  if (reply->error() != QNetworkReply::NoError) {
    emit errorOccurred(reply->errorString());
    setStatus(m_installedVersion.isEmpty() ? NotInstalled : Installed);
    reply->deleteLater();
    return;
  }

  QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
  QString tag = doc.object()["tag_name"].toString();
  setLatestVersion(tag);
  setStatus(m_installedVersion.isEmpty() ? NotInstalled : Installed);

  reply->deleteLater();
}

void YtDlpManager::install()
{
  logToFile(QStringLiteral("install() called, status=%1").arg(m_status));
  if (m_status == CheckingForUpdate || m_status == Downloading) {
    logToFile(QStringLiteral("install() ignored, already busy"));
    return;
  }

  QString assetName = releaseAssetName();
  QString downloadUrl = QString("https://github.com/yt-dlp/yt-dlp/releases/latest/download/%1").arg(assetName);
  logToFile(QStringLiteral("install() starting download: asset=%1 url=%2 buildCpuArch=%3")
    .arg(assetName, downloadUrl, QSysInfo::buildCpuArchitecture()));
  startDownload(downloadUrl);
}

void YtDlpManager::update()
{
  install();
}

void YtDlpManager::startDownload(QString const& downloadUrl)
{
  setStatus(Downloading);
  setProgress(0.0);

  QNetworkRequest request{QUrl(downloadUrl)};
  request.setMaximumRedirectsAllowed(10);
  request.setAttribute(QNetworkRequest::FollowRedirectsAttribute, QVariant(true));
  request.setRawHeader("User-Agent", "harbour-sailreel");

  m_activeReply = m_manager->get(request);
  logToFile(QStringLiteral("startDownload() request sent to %1").arg(downloadUrl));
  connect(m_activeReply, &QNetworkReply::downloadProgress, this, &YtDlpManager::onAssetDownloadProgress);
  connect(m_activeReply, &QNetworkReply::finished, this, &YtDlpManager::onAssetDownloadFinished);
}

void YtDlpManager::onAssetDownloadProgress(qint64 bytesReceived, qint64 bytesTotal)
{
  if (bytesTotal > 0) {
    setProgress(static_cast<float>(bytesReceived) / static_cast<float>(bytesTotal));
  }
}

void YtDlpManager::onAssetDownloadFinished()
{
  QNetworkReply* reply = m_activeReply;
  m_activeReply = nullptr;

  int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
  logToFile(QStringLiteral("asset download finished: error=%1 errorString=%2 httpStatus=%3 url=%4")
    .arg(reply->error()).arg(reply->errorString(), QString::number(httpStatus), reply->url().toString()));

  if (reply->error() != QNetworkReply::NoError) {
    QString message = reply->errorString();
    if (message.isEmpty()) {
      message = QStringLiteral("Network error downloading yt-dlp (HTTP %1)").arg(httpStatus);
    }
    emit errorOccurred(message);
    setStatus(m_installedVersion.isEmpty() ? NotInstalled : Installed);
    reply->deleteLater();
    return;
  }

  m_pendingData = reply->readAll();
  m_pendingAssetName = releaseAssetName();
  logToFile(QStringLiteral("asset downloaded: %1 bytes=%2").arg(m_pendingAssetName).arg(m_pendingData.size()));
  reply->deleteLater();

  if (m_pendingData.isEmpty()) {
    emit errorOccurred(QStringLiteral("Downloaded yt-dlp asset was empty (HTTP %1)").arg(httpStatus));
    setStatus(m_installedVersion.isEmpty() ? NotInstalled : Installed);
    return;
  }

  QNetworkRequest checksumRequest{QUrl(QStringLiteral("https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS"))};
  checksumRequest.setRawHeader("Accept", "text/plain");
  checksumRequest.setRawHeader("User-Agent", "harbour-sailreel");
  checksumRequest.setMaximumRedirectsAllowed(10);
  checksumRequest.setAttribute(QNetworkRequest::FollowRedirectsAttribute, QVariant(true));

  m_activeReply = m_manager->get(checksumRequest);
  connect(m_activeReply, &QNetworkReply::finished, this, &YtDlpManager::onChecksumReply);
}

void YtDlpManager::onChecksumReply()
{
  QNetworkReply* reply = m_activeReply;
  m_activeReply = nullptr;

  bool verified = false;
  QString verifyError;

  int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
  logToFile(QStringLiteral("checksum reply: error=%1 errorString=%2 httpStatus=%3")
    .arg(reply->error()).arg(reply->errorString(), QString::number(httpStatus)));

  if (reply->error() == QNetworkReply::NoError) {
    QByteArray checksumBody = reply->readAll();
    QStringList checksumLines = QString::fromUtf8(checksumBody)
      .split(QChar('\n'), QString::SkipEmptyParts);

    QByteArray hash = sha256(m_pendingData);
    QString expectedHash = QString::fromUtf8(hash.toHex());
    logToFile(QStringLiteral("checksum: expecting entry for %1 computedHash=%2 checksumLines=%3")
      .arg(m_pendingAssetName, expectedHash, QString::number(checksumLines.size())));

    for (QString const& line : checksumLines) {
      int spaceIdx = line.indexOf(QStringLiteral("  "));
      if (spaceIdx < 0) {
        continue;
      }
      QString lineHash = line.left(spaceIdx);
      QString lineName = line.mid(spaceIdx + 2);
      if ((lineName == m_pendingAssetName) && (lineHash.compare(expectedHash, Qt::CaseInsensitive) == 0)) {
        verified = true;
        break;
      }
    }
    if (!verified) {
      verifyError = QStringLiteral("SHA-256 checksum verification failed (HTTP %1, %2 lines received)")
        .arg(httpStatus).arg(checksumLines.size());
    }
  }
  else {
    verifyError = reply->errorString();
    if (verifyError.isEmpty()) {
      verifyError = QStringLiteral("Network error fetching checksum (HTTP %1)").arg(httpStatus);
    }
  }
  reply->deleteLater();

  if (!verified) {
    emit errorOccurred(verifyError);
    setStatus(m_installedVersion.isEmpty() ? NotInstalled : Installed);
    m_pendingData.clear();
    return;
  }

  QString path = binaryPath();
  QDir().mkpath(QFileInfo(path).absolutePath());

  bool ok = false;
  if (m_pendingAssetName.endsWith(QStringLiteral(".zip"))) {
    QString tmpZip = QString("%1.zip.new").arg(path);
    QFile zipFile(tmpZip);
    if (zipFile.open(QIODevice::WriteOnly)) {
      zipFile.write(m_pendingData);
      zipFile.close();

      QProcess unzip;
      unzip.setWorkingDirectory(QFileInfo(path).absolutePath());
      unzip.start(QStringLiteral("unzip"), QStringList() << QStringLiteral("-o") << tmpZip);
      ok = unzip.waitForFinished(30000) && (unzip.exitCode() == 0);
      QFile::remove(tmpZip);

      if (ok) {
        QDir dir(QFileInfo(path).absolutePath());
        QStringList entries = dir.entryList(QDir::Files);
        for (QString const& entry : entries) {
          if (entry != QFileInfo(path).fileName() && !entry.endsWith(QStringLiteral(".zip"))) {
            QFile::remove(path);
            ok = QFile::rename(dir.filePath(entry), path);
            break;
          }
        }
      }
    }
  }
  QString installError;
  if (!m_pendingAssetName.endsWith(QStringLiteral(".zip"))) {
    QString tempPath = path + QStringLiteral(".new");
    QFile tempFile(tempPath);
    ok = tempFile.open(QIODevice::WriteOnly);
    if (!ok) {
      installError = tempFile.errorString();
    }
    else {
      tempFile.write(m_pendingData);
      tempFile.close();
      // QFile::rename() refuses to overwrite an existing destination, so a
      // prior install (or a stale file) must be cleared first — the zip
      // branch above already does this before its own rename.
      QFile::remove(path);
      ok = tempFile.rename(path);
      if (!ok) {
        installError = tempFile.errorString();
      }
    }
  }

  m_pendingData.clear();

  logToFile(QStringLiteral("install write: ok=%1 path=%2 installError=%3")
    .arg(ok ? QStringLiteral("true") : QStringLiteral("false"), path, installError));

  if (ok) {
    QFile::setPermissions(path, QFile::permissions(path)
      | QFileDevice::ExeOwner | QFileDevice::ExeGroup | QFileDevice::ExeOther);
    refreshInstalledVersion();
  }
  else {
    QString detail = installError.isEmpty()
      ? QStringLiteral("Failed to install yt-dlp binary")
      : QStringLiteral("Failed to install yt-dlp binary: %1").arg(installError);
    emit errorOccurred(detail);
    setStatus(m_installedVersion.isEmpty() ? NotInstalled : Installed);
  }
}

QByteArray YtDlpManager::sha256(QByteArray const& data)
{
  return QCryptographicHash::hash(data, QCryptographicHash::Sha256);
}

QString YtDlpManager::getInstalledVersion()
{
  QProcess process;
  process.start(binaryPath(), QStringList() << QStringLiteral("--version"));
  if (process.waitForFinished(5000) && (process.exitCode() == 0)) {
    return QString::fromUtf8(process.readAllStandardOutput()).trimmed();
  }
  return QString();
}

void YtDlpManager::onVersionCheckFinished()
{
  QString version = m_versionWatcher.result();
  if (version.isEmpty()) {
    setInstalledVersion(QString());
    setStatus(Error);
  }
  else {
    setInstalledVersion(version);
    setStatus(Installed);
  }
}
