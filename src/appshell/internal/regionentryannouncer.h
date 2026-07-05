/*
 * SPDX-License-Identifier: GPL-3.0-only
 * MuseScore-Studio-CLA-applies
 *
 * MuseScore Studio
 * Music Composition & Notation
 *
 * Copyright (C) 2021 MuseScore Limited and others
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 3 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */
#ifndef MU_APPSHELL_REGIONENTRYANNOUNCER_H
#define MU_APPSHELL_REGIONENTRYANNOUNCER_H

#include <QString>
#include "modularity/ioc.h"
#include "async/asyncable.h"
#include "accessibility/iaccessibilitycontroller.h"
#include "context/iuicontextresolver.h"

namespace mu::appshell {
class RegionEntryAnnouncer : public muse::Contextable, public muse::async::Asyncable
{
    muse::ContextInject<context::IUiContextResolver> uiContextResolver = { this };
    muse::ContextInject<muse::accessibility::IAccessibilityController> accessibilityController = { this };

public:
    RegionEntryAnnouncer(const muse::modularity::ContextPtr& iocCtx)
        : muse::Contextable(iocCtx), m_lastContext(mu::context::UiCtxUnknown) {}

    void init();

private:
    void onContextChanged();
    QString messageForContext(const muse::ui::UiContext& ctx) const;

    muse::ui::UiContext m_lastContext;
};
}

#endif // MU_APPSHELL_REGIONENTRYANNOUNCER_H
