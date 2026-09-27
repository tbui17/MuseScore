/*
 * SPDX-License-Identifier: GPL-3.0-only
 * MuseScore-Studio-CLA-applies
 */

#include <gtest/gtest.h>
#include <gmock/gmock.h>

#include <memory>

#include <QAbstractItemModelTester>

#include "commandpalettemodel.h"
#include "actions/tests/mocks/actionsdispatchermock.h"
#include "mocks/accessibilitycontrollermock.h"
#include "mocks/appshellconfigurationmock.h"
#include "mocks/uiactionsregistermock.h"

using namespace mu::appshell;
using namespace muse::actions;
using namespace muse::ui;
using namespace testing;

class CommandPaletteAccessibilityTests : public ::testing::Test
{
protected:
    using ActionsMock = NiceMock<UiActionsRegisterMock>;
    using ConfigurationMock = StrictMock<AppShellConfigurationMock>;
    using DispatcherMock = StrictMock<ActionsDispatcherMock>;
    using AccessibilityMock = StrictMock<AccessibilityControllerMock>;

    void SetUp() override
    {
        UiAction about;
        about.code = "about-musescore";
        about.title = muse::TranslatableString("action", "About MuseScore");
        UiAction preferences;
        preferences.code = "preferences";
        preferences.title = muse::TranslatableString("action", "Preferences");
        const UiActionList actions = { about, preferences };

        ON_CALL(*m_actions, actionList()).WillByDefault(Return(actions));
        ON_CALL(*m_actions, actionState(_)).WillByDefault(Return(UiActionState::make_enabled()));
        ON_CALL(*m_actions, actionsChanged()).WillByDefault(Return(m_actionsChanged));
        ON_CALL(*m_actions, actionStateChanged()).WillByDefault(Return(m_actionStateChanged));

        m_model = std::make_unique<CommandPaletteModel>();
        m_model->configuration.set(m_configuration);
        m_model->uiActionsRegister.set(m_actions);
        m_model->dispatcher.set(m_dispatcher);
        m_model->accessibilityController.set(m_accessibility);
    }

    muse::async::Channel<UiActionList> m_actionsChanged;
    muse::async::Channel<ActionCodeList> m_actionStateChanged;
    std::shared_ptr<ActionsMock> m_actions = std::make_shared<ActionsMock>();
    std::shared_ptr<ConfigurationMock> m_configuration = std::make_shared<ConfigurationMock>();
    std::shared_ptr<DispatcherMock> m_dispatcher = std::make_shared<DispatcherMock>();
    std::shared_ptr<AccessibilityMock> m_accessibility = std::make_shared<AccessibilityMock>();
    // Destroy the model before its injected services and channel owners.
    std::unique_ptr<CommandPaletteModel> m_model;
};

TEST_F(CommandPaletteAccessibilityTests, SearchEditingDoesNotAnnounce)
{
    EXPECT_CALL(*m_accessibility, announce(_)).Times(0);
    m_model->load();
    m_model->setSearchText("about");
    m_model->setSearchText("zzz-no-match");
    m_model->setSearchText("");
    EXPECT_EQ(m_model->resultCount(), 2);
}

TEST_F(CommandPaletteAccessibilityTests, EmptyNavigationAnnouncesNoMatches)
{
    m_model->load();
    m_model->setSearchText("zzz-no-match");
    EXPECT_CALL(*m_accessibility, announce(m_model->emptyStateText())).Times(2);
    m_model->moveSelection(1);
    m_model->moveSelection(-1);
    EXPECT_EQ(m_model->selectedIndex(), -1);
}

TEST_F(CommandPaletteAccessibilityTests, EmptySelectionDoesNotDispatchOrUpdateHistory)
{
    m_model->load();
    m_model->setSearchText("zzz-no-match");
    EXPECT_FALSE(m_model->runSelected());
    EXPECT_FALSE(m_model->run(0));
    // Strict mocks reject any dispatch or history write, including during load.
}

TEST_F(CommandPaletteAccessibilityTests, ResultNavigationAnnouncesSelectionAndPosition)
{
    m_model->load();
    EXPECT_CALL(*m_accessibility, announce(QStringLiteral("Preferences, 2 of 2")));
    m_model->moveSelection(1);
    EXPECT_EQ(m_model->selectedIndex(), 1);

    EXPECT_CALL(*m_accessibility, announce(QStringLiteral("About MuseScore, 1 of 2")));
    m_model->moveSelection(-1);
    EXPECT_EQ(m_model->selectedIndex(), 0);
}

TEST_F(CommandPaletteAccessibilityTests, SearchRecoversFromNoMatches)
{
    m_model->load();
    m_model->setSearchText("zzz-no-match");
    EXPECT_CALL(*m_accessibility, announce(m_model->emptyStateText()));
    m_model->moveSelection(1);
    m_model->setSearchText("about");
    ASSERT_EQ(m_model->resultCount(), 1);
    ASSERT_EQ(m_model->selectedIndex(), 0);
    EXPECT_CALL(*m_accessibility, announce(QStringLiteral("About MuseScore, 1 of 1")));
    m_model->moveSelection(-1);
}

TEST_F(CommandPaletteAccessibilityTests, ProgrammaticSelectionDoesNotAnnounce)
{
    m_model->load();
    EXPECT_CALL(*m_accessibility, announce(_)).Times(0);
    m_model->setSelectedIndex(1);
    m_model->setSelectedIndex(0);
    EXPECT_EQ(m_model->selectedIndex(), 0);
}

TEST_F(CommandPaletteAccessibilityTests, ListItemsHaveNoChildRows)
{
    m_model->load();
    const QModelIndex item = m_model->index(0, 0);
    ASSERT_TRUE(item.isValid());
    EXPECT_EQ(m_model->rowCount(item), 0);
    EXPECT_EQ(m_model->rowCount(), 2);
}

TEST_F(CommandPaletteAccessibilityTests, QtModelContractSurvivesFilteringAndReset)
{
    QAbstractItemModelTester tester(m_model.get(), QAbstractItemModelTester::FailureReportingMode::Fatal);
    m_model->load();
    m_model->setSearchText("about");
    m_model->setSearchText("zzz-no-match");
    m_model->setSearchText("");
    EXPECT_EQ(m_model->resultCount(), 2);
}
