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
using ::testing::InSequence;

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

    // Use InSequence to assert: dispatch does NOT happen synchronously
    // during runSelected(), but DOES happen after the event loop processes
    // the deferred invocation.
    {
        InSequence seq;
        EXPECT_CALL(m_dispatcherMock, dispatch(action.code))
            .Times(0);
        EXPECT_CALL(m_dispatcherMock, dispatch(action.code))
            .Times(1);
    }

    m_model.setSelectedIndex(0);
    bool result = m_model.runSelected();
    EXPECT_TRUE(result);

    // Process deferred events — the QueuedConnection dispatch fires here.
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
