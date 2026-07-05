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
#include "regionentryannouncer.h"

#include "translation.h"
#include "log.h"

using namespace mu::appshell;
using namespace muse;
using namespace muse::ui;

void RegionEntryAnnouncer::init()
{
    if (!uiContextResolver()) {
        return;
    }

    uiContextResolver()->currentUiContextChanged().onNotify(this, [this]() {
        onContextChanged();
    });
}

void RegionEntryAnnouncer::onContextChanged()
{
    if (!uiContextResolver() || !accessibilityController()) {
        return;
    }

    const UiContext& ctx = uiContextResolver()->currentUiContext();
    QString message = messageForContext(ctx);
    if (message.isEmpty()) {
        return;
    }

    accessibilityController()->announce(message);
}

QString RegionEntryAnnouncer::messageForContext(const muse::ui::UiContext& ctx) const
{
    using namespace mu::context;

    if (ctx == UiCtxProjectFocused) {
        return muse::qtrc("appshell", "Score view");
    }
    if (ctx == UiCtxProjectOpened) {
        return muse::qtrc("appshell", "Score view");
    }
    if (ctx == UiCtxBrailleFocused) {
        return muse::qtrc("appshell", "Braille view");
    }
    if (ctx == UiCtxHomeOpened) {
        return muse::qtrc("appshell", "Home");
    }
    if (ctx == UiCtxPublishOpened) {
        return muse::qtrc("appshell", "Publish");
    }
    if (ctx == UiCtxDevToolsOpened) {
        return muse::qtrc("appshell", "DevTools");
    }
    // UiCtxDialogOpened: Qt announces dialogs natively — skip
    // UiCtxUnknown, UiCtxAny: nothing meaningful to say — skip
    return QString();
}
