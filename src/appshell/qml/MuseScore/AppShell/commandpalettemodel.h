/*
 * SPDX-License-Identifier: GPL-3.0-only
 * MuseScore-Studio-CLA-applies
 */

#pragma once

#include <QAbstractListModel>
#include <qqmlintegration.h>

#include "actions/iactionsdispatcher.h"
#include "async/asyncable.h"
#include "iappshellconfiguration.h"
#include "modularity/ioc.h"
#include "ui/iuiactionsregister.h"

#include "accessibility/iaccessibilitycontroller.h"

namespace mu::appshell {
class CommandPaletteModel : public QAbstractListModel, public muse::Contextable, public muse::async::Asyncable
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString searchText READ searchText WRITE setSearchText NOTIFY searchTextChanged)
    Q_PROPERTY(int selectedIndex READ selectedIndex WRITE setSelectedIndex NOTIFY selectedIndexChanged)
    Q_PROPERTY(QString emptyStateText READ emptyStateText NOTIFY emptyStateTextChanged)
    Q_PROPERTY(int resultCount READ resultCount NOTIFY resultCountChanged)

public:
    muse::GlobalInject<IAppShellConfiguration> configuration;
    muse::ContextInject<muse::ui::IUiActionsRegister> uiActionsRegister = { this };
    muse::ContextInject<muse::actions::IActionsDispatcher> dispatcher = { this };

    muse::ContextInject<muse::accessibility::IAccessibilityController> accessibilityController = { this };

    explicit CommandPaletteModel(QObject* parent = nullptr);

    QVariant data(const QModelIndex& index, int role) const override;
    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString searchText() const;
    void setSearchText(const QString& text);

    int selectedIndex() const;
    void setSelectedIndex(int index);

    QString emptyStateText() const;
    int resultCount() const;

    Q_INVOKABLE void load();
    Q_INVOKABLE void moveSelection(int delta);
    Q_INVOKABLE bool runSelected();
    Q_INVOKABLE bool run(int row);

signals:
    void searchTextChanged();
    void selectedIndexChanged();
    void emptyStateTextChanged();
    void resultCountChanged();

private:
    enum Roles {
        RoleTitle = Qt::UserRole + 1,
        RoleActionCode
    };

    struct Item {
        muse::actions::ActionCode actionCode;
        QString title;
        int sourceIndex = 0;
        int score = 0;
    };

    void ensureConnections();
    void reloadAvailableActions();
    void rebuildResults();
    QList<Item> recentItems() const;
    QList<Item> allItems() const;
    QList<Item> matchingItems() const;
    void setItems(const QList<Item>& items);
    void addRecentAction(const muse::actions::ActionCode& actionCode);
    bool isActionEnabled(const muse::actions::ActionCode& actionCode) const;
    int matchScore(const QString& title) const;
    QString makeEmptyStateText() const;

    QList<Item> m_availableActions;
    QList<Item> m_items;
    QString m_searchText;
    int m_selectedIndex = -1;
    bool m_connectionsInited = false;
};
}
