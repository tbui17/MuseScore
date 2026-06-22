/*
 * SPDX-License-Identifier: GPL-3.0-only
 * MuseScore-Studio-CLA-applies
 *
 * MuseScore Studio
 * Music Composition & Notation
 *
 * Copyright (C) 2024 MuseScore Limited and others
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 3
 * as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */
#pragma once

#include <gmock/gmock.h>

#include "appshell/iappshellconfiguration.h"

namespace mu::appshell {
class AppShellConfigurationMock : public IAppShellConfiguration
{
public:
    // First launch setup
    MOCK_METHOD(bool, hasCompletedFirstLaunchSetup, (), (const, override));
    MOCK_METHOD(void, setHasCompletedFirstLaunchSetup, (bool), (override));

    // Welcome dialog
    MOCK_METHOD(bool, welcomeDialogShowOnStartup, (), (const, override));
    MOCK_METHOD(void, setWelcomeDialogShowOnStartup, (bool), (override));
    MOCK_METHOD(muse::async::Notification, welcomeDialogShowOnStartupChanged, (), (const, override));

    MOCK_METHOD(std::string, welcomeDialogLastShownVersion, (), (const, override));
    MOCK_METHOD(void, setWelcomeDialogLastShownVersion, (const std::string&), (override));

    MOCK_METHOD(int, welcomeDialogLastShownIndex, (), (const, override));
    MOCK_METHOD(void, setWelcomeDialogLastShownIndex, (int), (override));

    // Startup mode
    MOCK_METHOD(StartupModeType, startupModeType, (), (const, override));
    MOCK_METHOD(void, setStartupModeType, (StartupModeType), (override));
    MOCK_METHOD(muse::async::Notification, startupModeTypeChanged, (), (const, override));

    MOCK_METHOD(muse::io::path_t, startupScorePath, (), (const, override));
    MOCK_METHOD(void, setStartupScorePath, (const muse::io::path_t&), (override));
    MOCK_METHOD(muse::async::Notification, startupScorePathChanged, (), (const, override));

    // Command palette
    MOCK_METHOD(muse::actions::ActionCodeList, commandPaletteRecentActions, (), (const, override));
    MOCK_METHOD(void, setCommandPaletteRecentActions, (const muse::actions::ActionCodeList&), (override));

    // URLs
    MOCK_METHOD(std::string, handbookUrl, (), (const, override));
    MOCK_METHOD(std::string, askForHelpUrl, (), (const, override));
    MOCK_METHOD(std::string, accessibilityStatementUrl, (), (const, override));
    MOCK_METHOD(std::string, museScoreUrl, (), (const, override));
    MOCK_METHOD(std::string, museScoreForumUrl, (), (const, override));
    MOCK_METHOD(std::string, museScoreContributionUrl, (), (const, override));
    MOCK_METHOD(std::string, museHubFreeMuseSoundsUrl, (), (const, override));
    MOCK_METHOD(std::string, musicXMLLicenseUrl, (), (const, override));
    MOCK_METHOD(std::string, musicXMLLicenseDeedUrl, (), (const, override));

    // Version info
    MOCK_METHOD(std::string, museScoreVersion, (), (const, override));
    MOCK_METHOD(std::string, museScoreRevision, (), (const, override));

    // Splash screen
    MOCK_METHOD(bool, needShowSplashScreen, (), (const, override));
    MOCK_METHOD(void, setNeedShowSplashScreen, (bool), (override));

    // Preferences dialog
    MOCK_METHOD(const QString&, preferencesDialogLastOpenedPageId, (), (const, override));
    MOCK_METHOD(void, setPreferencesDialogLastOpenedPageId, (const QString&), (override));

    // Settings edit
    MOCK_METHOD(void, startEditSettings, (), (override));
    MOCK_METHOD(void, applySettings, (), (override));
    MOCK_METHOD(void, rollbackSettings, (), (override));

    // Factory reset — default args stripped per gmock requirements
    MOCK_METHOD(void, revertToFactorySettings, (bool, bool, bool), (const, override));

    // Session
    MOCK_METHOD(muse::io::paths_t, sessionProjectsPaths, (), (const, override));
    MOCK_METHOD(muse::Ret, setSessionProjectsPaths, (const muse::io::paths_t&), (override));
};
}
