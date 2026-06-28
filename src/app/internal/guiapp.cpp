#include "guiapp.h"

#include "modularity/ioc.h"
#include "appshell/internal/istartupscenario.h"

#include "commandlineparser.h"

#include "testflow/itestflow.h"

#include "muse_framework_config.h"
#include "app_config.h"

#include "log.h"

#include <QTimer>

using namespace muse;
using namespace mu;
using namespace mu::app;
using namespace mu::appshell;

MuseScoreGuiApp::MuseScoreGuiApp(const std::shared_ptr<MuseScoreCmdOptions>& options)
    : muse::ui::GuiApplication(options)
{
}

MuseScoreGuiApp::SplashConfig MuseScoreGuiApp::splashConfig(const std::shared_ptr<CmdOptions>& opt) const
{
    std::shared_ptr<MuseScoreCmdOptions> options = std::dynamic_pointer_cast<MuseScoreCmdOptions>(opt);
    IF_ASSERT_FAILED(options) {
        return SplashConfig();
    }

    SplashConfig cfg;
    cfg.type = SplashScreen::Default;

    if (options->startup.type.has_value()) {
        if (options->startup.type.value() == "start-with-new") {
            cfg.type = SplashScreen::ForNewInstance;
            cfg.forNewScore = true;
        }
    } else if (options->startup.scoreUrl.has_value()) {
        project::ProjectFile file { options->startup.scoreUrl.value() };

        if (options->startup.scoreDisplayNameOverride.has_value()) {
            file.displayNameOverride = options->startup.scoreDisplayNameOverride.value();
        }

        cfg.type = SplashScreen::ForNewInstance;
        cfg.forNewScore = false;
        if (file.hasDisplayName()) {
            cfg.openingFileName = file.displayName(true /* includingExtension */);
        }
    }

    return cfg;
}

void MuseScoreGuiApp::showSplash()
{
#ifdef MUE_ENABLE_SPLASHSCREEN
    SplashConfig cfg = splashConfig(m_appOptions);
    if (cfg.type == SplashScreen::Default) {
        m_splashScreen = new SplashScreen(SplashScreen::Default);
        m_splashScreen->show();
    }
#endif
}

void MuseScoreGuiApp::showContextSplash(const muse::modularity::ContextPtr& ctxId)
{
 #ifdef MUE_ENABLE_SPLASHSCREEN
    SplashConfig cfg = splashConfig(contextData(ctxId).options);
    if (cfg.type == SplashScreen::ForNewInstance) {
        m_splashScreen = new SplashScreen(cfg.type, cfg.forNewScore, cfg.openingFileName);
        m_splashScreen->show();
    }
#endif
}

std::shared_ptr<muse::CmdOptions> MuseScoreGuiApp::makeContextOptions(const muse::StringList& args) const
{
    if (args.size() > 0) {
        std::vector<std::string> args_ = args.toStdStringList();
        args_.insert(args_.begin(), "dummy/path/to/app.exe");  // for compatibility
        const int argc = static_cast<int>(args_.size());
        std::vector<char*> argv(argc + 1, nullptr);
        for (int i = 0; i < argc; ++i) {
            argv[i] = args_[i].data();
        }
        argv[argc] = nullptr;

        CommandLineParser commandLineParser;
        commandLineParser.init();
        commandLineParser.parse(argc, argv.data());
        return commandLineParser.options();
    } else {
        return m_appOptions;
    }
}

QString MuseScoreGuiApp::mainWindowQmlPath(const QString& platform) const
{
    return QString(":/qt/qml/MuseScore/AppShell/platform/%1/Main.qml").arg(platform);
}

void MuseScoreGuiApp::doStartupScenario(const muse::modularity::ContextPtr& ctxId)
{
    auto startupScenario = muse::modularity::ioc(ctxId)->resolve<IStartupScenario>("app");

    //! NOTE Apply startup options
    const std::shared_ptr<MuseScoreCmdOptions> options = std::dynamic_pointer_cast<MuseScoreCmdOptions>(contextData(ctxId).options);
    IF_ASSERT_FAILED(options) {
        return;
    }

    startupScenario->setStartupType(options->startup.type);

    if (options->startup.scoreUrl.has_value()) {
        project::ProjectFile file = { options->startup.scoreUrl.value() };

        if (options->startup.scoreDisplayNameOverride.has_value()) {
            file.displayNameOverride = options->startup.scoreDisplayNameOverride.value();
        }

        startupScenario->setStartupScoreFile(file);
    }

    startupScenario->runOnSplashScreen();

    QString testflowScript = options->testflow.testCaseNameOrFile;

    QMetaObject::invokeMethod(qApp, [this, ctxId, startupScenario, testflowScript]() {
#ifdef MUE_ENABLE_SPLASHSCREEN
        if (m_splashScreen) {
            m_splashScreen->close();
            delete m_splashScreen;
            m_splashScreen = nullptr;
        }
#endif

        startupScenario->runAfterSplashScreen();

        if (!testflowScript.isEmpty()) {
           LOGI() << "doStartupScenario: scheduling testflow for " << testflowScript;
            // Defer until the QML main window is fully loaded so that
            // api.keyboard, api.navigation, and api.dispatcher have real
            // targets. The startup page is a local QML file that loads in
            // milliseconds; 2s is generous even on slow machines.
            QTimer::singleShot(2000, [this, ctxId]() {
                processTestflow(ctxId);
            });
        }
    }, Qt::QueuedConnection);
}

void MuseScoreGuiApp::applyCommandLineOptions(const std::shared_ptr<CmdOptions>& opt)
{
    GuiApplication::applyCommandLineOptions(opt);

    std::shared_ptr<MuseScoreCmdOptions> options = std::dynamic_pointer_cast<MuseScoreCmdOptions>(opt);
    IF_ASSERT_FAILED(options) {
        return;
    }

    if (options->app.revertToFactorySettings) {
        appshellConfiguration()->revertToFactorySettings(options->app.revertToFactorySettings.value());
    }

    if (guitarProConfiguration()) {
        if (options->guitarPro.experimental) {
            guitarProConfiguration()->setExperimental(true);
        }

        if (options->guitarPro.linkedTabStaffCreated) {
            guitarProConfiguration()->setLinkedTabStaffCreated(true);
        }
    }
}

void MuseScoreGuiApp::processTestflow(const muse::modularity::ContextPtr& ctxId)
{
    using namespace muse::testflow;

    LOGI() << "processTestflow: entered";

    muse::ContextInject<ITestflow> testflow = { ctxId };

    const std::shared_ptr<MuseScoreCmdOptions> options = std::dynamic_pointer_cast<MuseScoreCmdOptions>(contextData(ctxId).options);
    IF_ASSERT_FAILED(options) {
        QMetaObject::invokeMethod(qApp, []() { qApp->exit(1); }, Qt::QueuedConnection);
        return;
    }

    ITestflow::Options opt;
    opt.context = options->testflow.testCaseContextNameOrFile.toStdString();
    opt.contextVal = options->testflow.testCaseContextValue.toStdString();
    opt.func = options->testflow.testCaseFunc.toStdString();
    opt.funcArgs = options->testflow.testCaseFuncArgs.toStdString();

    // execScript is synchronous: it runs the JS script to completion,
    // sets status to Finished/Error, and calls restoreAffectOnServices()
    // before returning. We check the status after it returns and defer
    // the exit so the event loop can clean up before teardown.
    // We intentionally do NOT subscribe to statusChanged/stepStatusChanged
    // channels because those callbacks would outlive the Testflow singleton
    // during context destruction, causing a use-after-free SIGSEGV.
    testflow()->execScript(options->testflow.testCaseNameOrFile, opt);

    ITestflow::Status st = testflow()->status();
    int exitCode = (st == ITestflow::Status::Finished) ? 0 : 1;
    LOGI() << "processTestflow: finished with status " << ITestflow::statusToString(st).toStdString()
           << ", exit code " << exitCode;

    // Use std::exit instead of qApp->exit to avoid a SIGSEGV during context
    // teardown. execScript() calls affectOnServices() which replaces the
    // IInteractive implementation in the IoC; restoreAffectOnServices()
    // restores it, but the TestflowInteractive shared_ptr still references
    // the real IInteractive during context destruction. The destruction
    // order in BaseApplication::doDestroyContext (qDeleteAll on setups) can
    // free the real IInteractive before the Testflow singleton, causing a
    // use-after-free. Since execScript is synchronous and the test result is
    // already determined, we skip Qt teardown entirely.
    std::exit(exitCode);
}
