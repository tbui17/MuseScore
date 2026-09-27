/*
 * SPDX-License-Identifier: GPL-3.0-only
 * MuseScore-Studio-CLA-applies
 */

#pragma once

#include <gmock/gmock.h>

#include "accessibility/iaccessibilitycontroller.h"

namespace mu::appshell {
class AccessibilityControllerMock : public muse::accessibility::IAccessibilityController
{
public:
    using IAccessible = muse::accessibility::IAccessible;

    MOCK_METHOD(void, reg, (IAccessible*), (override));
    MOCK_METHOD(void, unreg, (IAccessible*), (override));
    MOCK_METHOD(bool, isReg, (IAccessible*), (const, override));
    MOCK_METHOD(void, announce, (const QString&), (override));
    MOCK_METHOD(QString, announcement, (), (const, override));
    MOCK_METHOD(const IAccessible*, accessibleRoot, (), (const, override));
    MOCK_METHOD(const IAccessible*, lastFocused, (), (const, override));
    MOCK_METHOD(bool, needToVoicePanelInfo, (), (const, override));
    MOCK_METHOD(QString, currentPanelAccessibleName, (), (const, override));
    MOCK_METHOD(bool, isEnabled, (), (const, override));
    MOCK_METHOD(void, setIgnoreQtAccessibilityEvents, (bool), (override));
};
}
