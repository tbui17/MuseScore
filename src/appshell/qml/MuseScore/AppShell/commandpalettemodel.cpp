/*
 * SPDX-License-Identifier: GPL-3.0-only
 * MuseScore-Studio-CLA-applies
 */

#include "commandpalettemodel.h"

#include <algorithm>

#include "translation.h"

using namespace mu::appshell;
using namespace muse::actions;
using namespace muse::ui;

static constexpr int MAX_RECENT_ACTIONS = 10;

CommandPaletteModel::CommandPaletteModel(QObject* parent)
    : QAbstractListModel(parent), muse::Contextable(muse::iocCtxForQmlObject(this))
{
}

QVariant CommandPaletteModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) {
        return QVariant();
    }

    const Item& item = m_items.at(index.row());
    switch (role) {
    case RoleTitle:
        return item.title;
    case RoleActionCode:
        return QString::fromStdString(item.actionCode);
    }

    return QVariant();
}

int CommandPaletteModel::rowCount(const QModelIndex&) const
{
    return m_items.size();
}

QHash<int, QByteArray> CommandPaletteModel::roleNames() const
{
    return {
        { RoleTitle, "title" },
        { RoleActionCode, "actionCode" }
    };
}

QString CommandPaletteModel::searchText() const
{
    return m_searchText;
}

void CommandPaletteModel::setSearchText(const QString& text)
{
    const QString trimmed = text.trimmed();
    if (m_searchText == trimmed) {
        return;
    }

    m_searchText = trimmed;
    emit searchTextChanged();
    rebuildResults();
}

int CommandPaletteModel::selectedIndex() const
{
    return m_selectedIndex;
}

void CommandPaletteModel::setSelectedIndex(int index)
{
    const int boundedIndex = m_items.isEmpty() ? -1 : std::clamp(index, 0, static_cast<int>(m_items.size()) - 1);
    if (m_selectedIndex == boundedIndex) {
        return;
    }

    m_selectedIndex = boundedIndex;
    emit selectedIndexChanged();
}

QString CommandPaletteModel::emptyStateText() const
{
    return makeEmptyStateText();
}

int CommandPaletteModel::resultCount() const
{
    return rowCount();
}

void CommandPaletteModel::load()
{
    ensureConnections();
    reloadAvailableActions();
    rebuildResults();
}

void CommandPaletteModel::moveSelection(int delta)
{
    if (m_items.isEmpty()) {
        setSelectedIndex(-1);
        return;
    }

    int nextIndex = m_selectedIndex < 0 ? 0 : m_selectedIndex + delta;
    nextIndex = std::clamp(nextIndex, 0, static_cast<int>(m_items.size()) - 1);
    setSelectedIndex(nextIndex);
}

bool CommandPaletteModel::runSelected()
{
    return run(m_selectedIndex);
}

bool CommandPaletteModel::run(int row)
{
    if (row < 0 || row >= m_items.size()) {
        return false;
    }

    const ActionCode actionCode = m_items.at(row).actionCode;
    addRecentAction(actionCode);
    dispatcher()->dispatch(actionCode);
    return true;
}

void CommandPaletteModel::ensureConnections()
{
    if (m_connectionsInited) {
        return;
    }

    uiActionsRegister()->actionsChanged().onReceive(this, [this](const UiActionList&) {
        reloadAvailableActions();
        rebuildResults();
    });

    uiActionsRegister()->actionStateChanged().onReceive(this, [this](const ActionCodeList&) {
        reloadAvailableActions();
        rebuildResults();
    });

    m_connectionsInited = true;
}

void CommandPaletteModel::reloadAvailableActions()
{
    m_availableActions.clear();

    int sourceIndex = 0;
    for (const UiAction& action : uiActionsRegister()->actionList()) {
        const QString title = action.title.qTranslatedWithoutMnemonic();
        if (title.isEmpty() || !isActionEnabled(action.code)) {
            ++sourceIndex;
            continue;
        }

        Item item;
        item.actionCode = action.code;
        item.title = title;
        item.sourceIndex = sourceIndex;
        m_availableActions << item;
        ++sourceIndex;
    }
}

void CommandPaletteModel::rebuildResults()
{
    setItems(m_searchText.isEmpty() ? allItems() : matchingItems());
    emit emptyStateTextChanged();
}

QList<CommandPaletteModel::Item> CommandPaletteModel::recentItems() const
{
    QList<Item> result;
    const ActionCodeList recentActions = configuration()->commandPaletteRecentActions();

    for (const ActionCode& recentAction : recentActions) {
        auto it = std::find_if(m_availableActions.cbegin(), m_availableActions.cend(), [recentAction](const Item& item) {
            return item.actionCode == recentAction;
        });

        if (it != m_availableActions.cend()) {
            result << *it;
        }
    }

    return result;
}

QList<CommandPaletteModel::Item> CommandPaletteModel::allItems() const
{
    return m_availableActions;
}

QList<CommandPaletteModel::Item> CommandPaletteModel::matchingItems() const
{
    QList<Item> result;

    for (Item item : m_availableActions) {
        item.score = matchScore(item.title);
        if (item.score > 0) {
            result << item;
        }
    }

    std::sort(result.begin(), result.end(), [](const Item& left, const Item& right) {
        if (left.score != right.score) {
            return left.score > right.score;
        }

        return QString::localeAwareCompare(left.title, right.title) < 0;
    });

    return result;
}

void CommandPaletteModel::setItems(const QList<Item>& items)
{
    beginResetModel();
    m_items = items;
    endResetModel();

    setSelectedIndex(m_items.isEmpty() ? -1 : 0);
    emit resultCountChanged();
}

void CommandPaletteModel::addRecentAction(const ActionCode& actionCode)
{
    ActionCodeList recentActions = configuration()->commandPaletteRecentActions();
    recentActions.erase(std::remove(recentActions.begin(), recentActions.end(), actionCode), recentActions.end());
    recentActions.insert(recentActions.begin(), actionCode);

    if (recentActions.size() > MAX_RECENT_ACTIONS) {
        recentActions.resize(MAX_RECENT_ACTIONS);
    }

    configuration()->setCommandPaletteRecentActions(recentActions);
}

bool CommandPaletteModel::isActionEnabled(const ActionCode& actionCode) const
{
    return uiActionsRegister()->actionState(actionCode).enabled;
}

int CommandPaletteModel::matchScore(const QString& title) const
{
    if (title.compare(m_searchText, Qt::CaseInsensitive) == 0) {
        return 100;
    }

    if (title.startsWith(m_searchText, Qt::CaseInsensitive)) {
        return 75;
    }

    if (title.contains(m_searchText, Qt::CaseInsensitive)) {
        return 50;
    }

    return 0;
}

QString CommandPaletteModel::makeEmptyStateText() const
{
    return muse::qtrc("appshell/commandpalette", "No matching commands");
}
