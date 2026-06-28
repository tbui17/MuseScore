#include <gtest/gtest.h>
#include <gmock/gmock.h>

#include "commandpalettemodel.h"

#include "actions/tests/mocks/actionsdispatchermock.h"
#include "mocks/uiactionsregistermock.h"
#include "mocks/appshellconfigurationmock.h"

#include <QTest>

using namespace mu::appshell;
using namespace muse::actions;
using namespace muse::ui;
using ::testing::_;
using ::testing::Return;

class CommandPaletteModelTests : public ::testing::Test
{
protected:
    void SetUp() override
    {
        // Inject mocks via the IoC set() method (ioc.h:100).
        // Custom deleter (no-op) prevents double-free: the mock is a
        // stack member, so we must not delete it when the shared_ptr
        // refcount hits zero.
        m_model.configuration.set(
            std::shared_ptr<IAppShellConfiguration>(&m_configMock, [](auto*) {}));
        m_model.uiActionsRegister.set(
            std::shared_ptr<IUiActionsRegister>(&m_uiActionsRegisterMock, [](auto*) {}));
        m_model.dispatcher.set(
            std::shared_ptr<IActionsDispatcher>(&m_dispatcherMock, [](auto*) {}));
    }

    CommandPaletteModel m_model;
    ActionsDispatcherMock m_dispatcherMock;
    UiActionsRegisterMock m_uiActionsRegisterMock;
    AppShellConfigurationMock m_configMock;
};

/**
 * When a command is run, the dispatch should be deferred (via queued
 * invocation) so that the palette dialog can close before the dispatched
 * action opens a new dialog. This prevents the new dialog's transient
 * parent from being the palette dialog.
 */
TEST_F(CommandPaletteModelTests, RunSelected_DefersDispatch)
{
    UiAction action;
    action.code = "about-musescore";
    action.title = muse::TranslatableString("action", "About MuseScore");

    UiActionList actions = { action };
    EXPECT_CALL(m_uiActionsRegisterMock, actionList())
        .WillOnce(Return(actions));
    EXPECT_CALL(m_uiActionsRegisterMock, actionState(action.code))
        .WillOnce(Return(UiActionState::make_enabled()));

    EXPECT_CALL(m_configMock, commandPaletteRecentActions())
        .WillOnce(Return(ActionCodeList()));

    m_model.load();

    // Expectation: dispatch does NOT happen synchronously during runSelected().
    // This is a strict expectation — any synchronous call to dispatch() will
    // fail the test. The expectation retires immediately (Times(0) is vacuously
    // satisfied), so the deferred call below won't match it.
    EXPECT_CALL(m_dispatcherMock, dispatch(action.code))
        .Times(0);

    m_model.setSelectedIndex(0);
    bool result = m_model.runSelected();
    EXPECT_TRUE(result);

    // Flush any synchronous expectations before the deferred call fires.
    testing::Mock::VerifyAndClearExpectations(&m_dispatcherMock);

    // After processing deferred events, the QueuedConnection dispatch fires.
    EXPECT_CALL(m_dispatcherMock, dispatch(action.code))
        .Times(1);

    QTest::qWait(10);
}

/**
 * Regression: when run() defers the dispatch, the deferred call must
 * survive the model's destruction. In production the model is a QML
 * child of CommandPaletteDialog and is destroyed when the dialog closes
 * (InteractiveProvider.qml:127 → obj.destroy() → deleteLater()).
 *
 * If the deferral posts via QMetaObject::invokeMethod(this, ...) with
 * Qt::QueuedConnection, QObject's destructor calls removePostedEvents,
 * which silently discards the pending QMetaCallEvent — the dispatch
 * never fires and the command appears to do nothing.
 *
 * This test destroys the model between runSelected() and the event
 * loop flush, then asserts dispatch still fires. Against the old
 * invokeMethod(this,...) code this test FAILS (dispatch dropped).
 * Against the QTimer::singleShot fix it PASSES.
 */
TEST_F(CommandPaletteModelTests, RunSelected_DispatchSurvivesModelDestruction)
{
    UiAction action;
    action.code = "about-musescore";
    action.title = muse::TranslatableString("action", "About MuseScore");

    UiActionList actions = { action };
    EXPECT_CALL(m_uiActionsRegisterMock, actionList())
        .WillOnce(Return(actions));
    EXPECT_CALL(m_uiActionsRegisterMock, actionState(action.code))
        .WillOnce(Return(UiActionState::make_enabled()));

    EXPECT_CALL(m_configMock, commandPaletteRecentActions())
        .WillOnce(Return(ActionCodeList()));

    // Heap-allocate the model so we can destroy it mid-flight, exactly
    // like the dialog destroying its QML child. The mocks are injected
    // via the no-op-deleter shared_ptr pattern from SetUp.
    auto model = std::make_unique<CommandPaletteModel>();
    model->configuration.set(
        std::shared_ptr<IAppShellConfiguration>(&m_configMock, [](auto*) {}));
    model->uiActionsRegister.set(
        std::shared_ptr<IUiActionsRegister>(&m_uiActionsRegisterMock, [](auto*) {}));
    model->dispatcher.set(
        std::shared_ptr<IActionsDispatcher>(&m_dispatcherMock, [](auto*) {}));

    model->load();
    model->setSelectedIndex(0);

    EXPECT_CALL(m_dispatcherMock, dispatch(action.code))
        .Times(0);
    bool result = model->runSelected();
    EXPECT_TRUE(result);
    testing::Mock::VerifyAndClearExpectations(&m_dispatcherMock);

    // Destroy the model — simulates the dialog closing and its QML child
    // being garbage-collected. With the old code this would cause
    // removePostedEvents to drop the pending QMetaCallEvent.
    model.reset();

    // The dispatch must still fire despite the model being gone.
    EXPECT_CALL(m_dispatcherMock, dispatch(action.code))
        .Times(1);
    QTest::qWait(10);
}

TEST_F(CommandPaletteModelTests, RunSelected_NoAction)
{
    m_model.setSelectedIndex(-1);
    bool result = m_model.runSelected();
    EXPECT_FALSE(result);
}

TEST_F(CommandPaletteModelTests, Run_InvalidRow)
{
    bool result = m_model.run(-1);
    EXPECT_FALSE(result);
    result = m_model.run(999);
    EXPECT_FALSE(result);
}
