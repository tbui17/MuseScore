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

#include "ui/iuiactionsregister.h"

namespace muse::ui {
class UiActionsRegisterMock : public IUiActionsRegister
{
public:
    MOCK_METHOD(void, reg, (const IUiActionsModulePtr&), (override));
    MOCK_METHOD(void, unreg, (const IUiActionsModulePtr&), (override));

    MOCK_METHOD(std::vector<UiAction>, actionList, (), (const, override));

    MOCK_METHOD(const UiAction&, action, (const actions::ActionCode&), (const, override));
    MOCK_METHOD(const actions::ActionCode&, parentActionCode, (const actions::ActionCode&), (const, override));
    MOCK_METHOD(async::Channel<UiActionList>, actionsChanged, (), (const, override));

    MOCK_METHOD(UiActionState, actionState, (const actions::ActionCode&), (const, override));
    MOCK_METHOD(async::Channel<actions::ActionCodeList>, actionStateChanged, (), (const, override));
};
}
