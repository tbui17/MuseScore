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
#include <gmock/gmock.h>

#include "mocks/controlledviewmock.h"
#include "notation/tests/mocks/notationconfigurationmock.h"
#include "notation/tests/mocks/notationinteractionmock.h"
#include "notation/tests/mocks/notationselectionmock.h"
#include "notation/tests/mocks/notationselectionrangemock.h"
#include "playback/tests/mocks/playbackcontrollermock.h"

#include "braille/ibrailleconfiguration.h"
#include "braille/inotationbraille.h"
#include "notation/inotationnoteinput.h"

#include "engraving/tests/utils/scorerw.h"

#include "notationscene/qml/MuseScore/NotationScene/notationviewinputcontroller.h"

using ::testing::_;
using ::testing::Mock;
using ::testing::NiceMock;
using ::testing::Return;
using ::testing::ReturnRef;
using ::testing::InSequence;

using namespace mu;
using namespace mu::notation;
using namespace mu::braille;
using namespace muse;

static const String TEST_SCORE_PATH(u"data/test.mscx");
static constexpr bool FLUSH_SOUND = true;

class BrailleConfigurationMock : public IBrailleConfiguration
{
public:
    MOCK_METHOD(muse::async::Notification, braillePanelEnabledChanged, (), (const, override));
    MOCK_METHOD(bool, braillePanelEnabled, (), (const, override));
    MOCK_METHOD(void, setBraillePanelEnabled, (const bool), (override));

    MOCK_METHOD(muse::async::Notification, sixKeyInputEnabledChanged, (), (const, override));
    MOCK_METHOD(bool, sixKeyInputEnabled, (), (const, override));
    MOCK_METHOD(void, setSixKeyInputEnabled, (const bool), (override));
    MOCK_METHOD(muse::async::Notification, advanceCursorAfterDotChanged, (), (const, override));
    MOCK_METHOD(bool, advanceCursorAfterDot, (), (const, override));
    MOCK_METHOD(void, setAdvanceCursorAfterDot, (const bool), (override));

    MOCK_METHOD(muse::async::Notification, intervalDirectionChanged, (), (const, override));
    MOCK_METHOD(BrailleIntervalDirection, intervalDirection, (), (const, override));
    MOCK_METHOD(void, setIntervalDirection, (const BrailleIntervalDirection), (override));

    MOCK_METHOD(muse::async::Notification, brailleTableChanged, (), (const, override));
    MOCK_METHOD(QString, brailleTable, (), (const, override));
    MOCK_METHOD(void, setBrailleTable, (const QString&), (override));
    MOCK_METHOD(QStringList, brailleTableList, (), (const, override));
};

class NotationBrailleMock : public INotationBraille
{
public:
    MOCK_METHOD(muse::ValCh<std::string>, brailleInfo, (), (const, override));
    MOCK_METHOD(muse::ValCh<int>, cursorPosition, (), (const, override));
    MOCK_METHOD(muse::ValCh<int>, currentItemPositionStart, (), (const, override));
    MOCK_METHOD(muse::ValCh<int>, currentItemPositionEnd, (), (const, override));
    MOCK_METHOD(muse::ValCh<std::string>, keys, (), (const, override));
    MOCK_METHOD(muse::ValCh<bool>, enabled, (), (const, override));
    MOCK_METHOD(muse::ValCh<BrailleIntervalDirection>, intervalDirection, (), (const, override));
    MOCK_METHOD(muse::ValCh<int>, mode, (), (const, override));
    MOCK_METHOD(muse::ValCh<std::string>, cursorColor, (), (const, override));

    MOCK_METHOD(void, setEnabled, (const bool), (override));
    MOCK_METHOD(void, setIntervalDirection, (const BrailleIntervalDirection), (override));
    MOCK_METHOD(void, setCursorPosition, (const int), (override));
    MOCK_METHOD(void, setCurrentItemPosition, (const int, const int), (override));
    MOCK_METHOD(void, setKeys, (const QString&), (override));
    MOCK_METHOD(void, clearPendingInput, (), (override));
    MOCK_METHOD(void, setMode, (const BrailleMode), (override));
    MOCK_METHOD(void, toggleMode, (), (override));
    MOCK_METHOD(bool, isNavigationMode, (), (override));
    MOCK_METHOD(bool, isBrailleInputMode, (), (override));
    MOCK_METHOD(void, setCursorColor, (const QString), (override));
};

class NotationNoteInputMock : public INotationNoteInput
{
public:
    MOCK_METHOD(bool, isNoteInputMode, (), (const, override));
    MOCK_METHOD(const NoteInputState&, state, (), (const, override));
    MOCK_METHOD(void, startNoteInput, (NoteInputMethod, bool), (override));
    MOCK_METHOD(void, endNoteInput, (bool), (override));
    MOCK_METHOD(muse::async::Channel<bool>, noteInputStarted, (), (const, override));
    MOCK_METHOD(muse::async::Notification, noteInputEnded, (), (const, override));
    MOCK_METHOD(bool, usingNoteInputMethod, (NoteInputMethod), (const, override));
    MOCK_METHOD(void, setNoteInputMethod, (NoteInputMethod), (override));
    MOCK_METHOD(void, addNote, (const NoteInputParams&, NoteAddingMode), (override));
    MOCK_METHOD(void, padNote, (const Pad&), (override));
    MOCK_METHOD(muse::Ret, putNote, (const muse::PointF&, bool, bool), (override));
    MOCK_METHOD(void, removeNote, (const muse::PointF&), (override));
    MOCK_METHOD(void, addTuplet, (const TupletOptions&), (override));
    MOCK_METHOD(void, doubleNoteInputDuration, (), (override));
    MOCK_METHOD(void, halveNoteInputDuration, (), (override));
    MOCK_METHOD(void, addSlur, (mu::engraving::Slur*), (override));
    MOCK_METHOD(void, resetSlur, (), (override));
    MOCK_METHOD(void, addTie, (), (override));
    MOCK_METHOD(void, addLaissezVib, (), (override));
    MOCK_METHOD(void, setInputNote, (const NoteInputParams&), (override));
    MOCK_METHOD(void, setInputNotes, (const NoteValList&), (override));
    MOCK_METHOD(void, moveInputNotes, (bool, PitchMode), (override));
    MOCK_METHOD(void, setRestMode, (bool), (override));
    MOCK_METHOD(void, setAccidental, (AccidentalType), (override));
    MOCK_METHOD(void, setArticulation, (SymbolId), (override));
    MOCK_METHOD(void, setDrumNote, (int), (override));
    MOCK_METHOD(void, setCurrentVoice, (voice_idx_t), (override));
    MOCK_METHOD(void, setCurrentTrack, (track_idx_t), (override));
    MOCK_METHOD(muse::RectF, cursorRect, (), (const, override));
    MOCK_METHOD(muse::async::Notification, noteAdded, (), (const, override));
    MOCK_METHOD(muse::async::Notification, stateChanged, (), (const, override));
    MOCK_METHOD(void, advanceCursor, (), (override));
};

class NotationViewInputControllerTests : public ::testing::Test
{
public:

    void SetUp() override
    {
        m_interaction = std::make_shared<NiceMock<NotationInteractionMock> >();

        m_selection = std::make_shared<NiceMock<NotationSelectionMock> >();
        ON_CALL(*m_interaction, selection())
        .WillByDefault(Return(m_selection));

        m_selectionRange = std::make_shared<NiceMock<NotationSelectionRangeMock> >();
        ON_CALL(*m_selection, range())
        .WillByDefault(Return(m_selectionRange));

        ON_CALL(m_view, notationInteraction())
        .WillByDefault(Return(m_interaction));

        ON_CALL(m_view, currentScaling())
        .WillByDefault(Return(1));

        m_controller = new NotationViewInputController(&m_view, muse::modularity::globalCtx());

        m_configuration = std::make_shared<NiceMock<NotationConfigurationMock> >();
        m_controller->configuration.set(m_configuration);

        m_brailleConfiguration = std::make_shared<BrailleConfigurationMock>();
        m_controller->brailleConfiguration.set(m_brailleConfiguration);

        m_notationBraille = std::make_shared<NiceMock<NotationBrailleMock> >();
        m_controller->notationBraille.set(m_notationBraille);

        m_noteInput = std::make_shared<NiceMock<NotationNoteInputMock> >();
        ON_CALL(*m_interaction, noteInput()).WillByDefault(Return(m_noteInput));
        ON_CALL(*m_noteInput, state()).WillByDefault(ReturnRef(m_noteInputState));
        ON_CALL(*m_configuration, defaultNoteInputMethod()).WillByDefault(Return(NoteInputMethod::BY_NOTE_NAME));

        m_playbackController = std::make_shared<NiceMock<playback::PlaybackControllerMock> >();
        m_controller->playbackController.set(m_playbackController);

        setNoWaylandForLinux();
    }

    void TearDown() override
    {
        qDeleteAll(m_events);
        delete m_controller;
    }

    NotationViewInputController* m_controller = nullptr;
    NiceMock<ControlledViewMock> m_view;
    std::shared_ptr<NotationConfigurationMock> m_configuration;
    std::shared_ptr<NotationInteractionMock> m_interaction;
    std::shared_ptr<NotationSelectionMock> m_selection;
    std::shared_ptr<NotationSelectionRangeMock> m_selectionRange;
    std::shared_ptr<playback::PlaybackControllerMock> m_playbackController;
    playback::IPlaybackController::PlayParams m_playParams;
    std::shared_ptr<BrailleConfigurationMock> m_brailleConfiguration;
    std::shared_ptr<NotationBrailleMock> m_notationBraille;
    std::shared_ptr<NotationNoteInputMock> m_noteInput;
    NoteInputState m_noteInputState;

    mutable QList<QInputEvent*> m_events;

    struct HitContextConfig
    {
        ElementType elementType = ElementType::INVALID;
        bool start = true;
    };

    QWheelEvent* make_wheelEvent(QPoint pixelDelta,
                                 QPoint angleDelta,
                                 Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                                 QPointF pos = QPointF(100, 100)) const
    {
        QPointF globalPos = pos;
        Qt::MouseButtons buttons = Qt::NoButton;

        QWheelEvent* ev = new QWheelEvent(pos,  globalPos,  pixelDelta,  angleDelta,
                                          buttons, modifiers, Qt::ScrollPhase::NoScrollPhase, false);

        m_events << ev;

        return ev;
    }

    QMouseEvent* make_mousePressEvent(
        Qt::MouseButton button,
        Qt::KeyboardModifiers modifiers = Qt::NoModifier,
        QPointF pos = QPointF(100, 100)) const
    {
        QMouseEvent* ev = new QMouseEvent(QMouseEvent::Type::MouseButtonPress, pos, pos, button, {}, modifiers);

        m_events << ev;

        return ev;
    }

    QKeyEvent* make_keyEvent(QEvent::Type type, int key, Qt::KeyboardModifiers modifiers = Qt::NoModifier,
                             bool autoRepeat = false) const
    {
        QKeyEvent* ev = new QKeyEvent(type, key, modifiers, QString(), autoRepeat);
        ev->ignore();
        m_events << ev;
        return ev;
    }

    notation::EngravingItem* findElement(ElementType type, ChordRest* chord) const
    {
        switch (type) {
        case ElementType::NOTE:
            return engraving::toChord(chord)->notes().front();
        case ElementType::DYNAMIC: {
            for (notation::EngravingItem* element : chord->segment()->annotations()) {
                if (element->isDynamic()) {
                    return element;
                }
            }
            break;
        }
        case ElementType::HAIRPIN: {
            const mu::engraving::SpannerMap& spannerMap = chord->score()->spannerMap();
            auto intervals = spannerMap.findOverlapping(0, chord->score()->endTick().ticks());
            for (const auto& interval : intervals) {
                mu::engraving::Spanner* spanner = interval.value;
                if (spanner->isHairpin()) {
                    return spanner;
                }
            }
            break;
        }
        case ElementType::MEASURE:
            return chord->segment()->measure();
        default:
            break;
        }

        return nullptr;
    }

    INotationInteraction::HitElementContext hitContext(engraving::MasterScore* score, HitContextConfig config) const
    {
        INotationInteraction::HitElementContext context;

        Measure* firstMeasure = score->firstMeasure();
        Segment* segment = config.start ? firstMeasure->segments().firstCRSegment() : firstMeasure->segments().last();
        ChordRest* chord = segment->nextChordRest(0, !config.start);

        context.element = findElement(config.elementType, chord);
        context.staff = context.element->staff();

        return context;
    }

    INotationInteraction::HitElementContext hitMeasureContext(engraving::MasterScore* score, int index) const
    {
        INotationInteraction::HitElementContext context;

        engraving::MeasureBase* measure = score->measure(index);
        context.element = measure;
        context.staff = score->staff(0);

        return context;
    }

    void setNoWaylandForLinux()
    {
#ifdef Q_OS_LINUX
        //! [GIVEN] No Wayland display
        setenv("WAYLAND_DISPLAY", "OFF", false);
#endif
    }
};

namespace mu::playback {
inline bool operator==(const IPlaybackController::PlayParams& p1, const IPlaybackController::PlayParams& p2)
{
    return p1.duration == p2.duration && p1.flushSound == p2.flushSound;
}
}

/**
 * @brief WheelEvent_ScrollVertical
 * @details Received wheel event, without modifiers
 */
TEST_F(NotationViewInputControllerTests, WheelEvent_ScrollVertical)
{
    //! [THEN] Should be called vertical scroll with value 180
    EXPECT_CALL(m_view, moveCanvas(0, 180))
    .Times(1);

    //! [WHEN] User scrolled mouse wheel
    m_controller->wheelEvent(make_wheelEvent(QPoint(0, 180), QPoint(0, 120)));

    //! [THEN] Should be called vertical scroll with value 80
    EXPECT_CALL(m_view, moveCanvas(0, 80))
    .Times(1);

    //! [WHEN] User scrolled mouse wheel
    m_controller->wheelEvent(make_wheelEvent(QPoint(0, 80), QPoint(0, 120)));

    //! [GIVEN] pixelDelta is Null
    //!  dy = (angleDelta.y() * qMax(2.0, m_view->height() / 10.0)) / QWheelEvent::DefaultDeltasPerStep;

    //! [THEN] Should be called vertical scroll with value 50  (dy = (120 * 500 / 10) / 120 = 50)
    EXPECT_CALL(m_view, moveCanvas(0, 50))
    .Times(1);

    EXPECT_CALL(m_view, height())
    .WillOnce(Return(500));

    //! [WHEN] User scrolled mouse wheel
    m_controller->wheelEvent(make_wheelEvent(QPoint(), QPoint(0, 120)));
}

/**
 * @brief WheelEvent_ScrollHorizontal
 * @details Received wheel event, with key modifier ShiftModifier
 */
TEST_F(NotationViewInputControllerTests, WheelEvent_ScrollHorizontal)
{
    //! [THEN] Should be called horizontal scroll with value 120
    EXPECT_CALL(m_view, moveCanvasHorizontal(120))
    .Times(1);

    //! [WHEN] User scrolled mouse wheel
    m_controller->wheelEvent(make_wheelEvent(QPoint(0, 120), QPoint(), Qt::ShiftModifier));
}

/**
 * @brief WheelEvent_ScrollHorizontal
 * @details Received wheel event, with key modifier ControlModifier
 */
TEST_F(NotationViewInputControllerTests, DISABLED_WheelEvent_Zoom)
{
    //! CASE Received wheel event, with key modifier ControlModifier
    ValCh<int> currentZoom;
    currentZoom.val = 100;

//    ON_CALL(*m_configuration, currentZoom())
//    .WillByDefault(Return(currentZoom));

    //! CHECK Should be called zoomStep with value 110
//    EXPECT_CALL(env.view, setZoom(110, QPoint(100, 100)))
//    .Times(1);

    EXPECT_CALL(m_view, height())
    .WillOnce(Return(500));

    EXPECT_CALL(m_view, toLogical(QPointF(100, 100)))
    .WillOnce(Return(PointF(100, 100)));

    m_controller->wheelEvent(make_wheelEvent(QPoint(), QPoint(0, 120), Qt::ControlModifier, QPointF(100, 100)));
}

/**
 * @brief Mouse_Press_Range_Start_Drag_From_Selected_Element
 * @details User pressed left mouse button on already selected note
 *          The new note should be seeked and played, but no selected again
 */
TEST_F(NotationViewInputControllerTests, Mouse_Press_Range_Start_Drag_From_Selected_Element)
{
    //! [GIVEN] There is a test score
    engraving::MasterScore* score = engraving::ScoreRW::readScore(TEST_SCORE_PATH);

    //! [GIVEN] User selected new note that was already selected
    INotationInteraction::HitElementContext newContext = hitContext(score, { ElementType::NOTE, false /*last note*/ });
    newContext.element->setSelected(true);

    std::vector<EngravingItem*> selectedElements {
        newContext.element
    };

    EXPECT_CALL(*m_interaction, hitElement(_, _))
    .WillOnce(Return(newContext.element));

    EXPECT_CALL(*m_interaction, hitStaff(_))
    .WillOnce(Return(newContext.element->staff()));

    //! [THEN] The new hit element context with new note will be set
    EXPECT_CALL(*m_interaction, setHitElementContext(newContext))
    .Times(1);

    ON_CALL(*m_interaction, hitElementContext())
    .WillByDefault(ReturnRef(newContext));

    //! [GIVEN] There is a range selection
    ON_CALL(*m_selection, isRange())
    .WillByDefault(Return(true));

    ON_CALL(*m_selection, elements())
    .WillByDefault(ReturnRef(selectedElements));

    //! [GIVEN] No note enter mode, no playing
    EXPECT_CALL(m_view, isNoteEnterMode())
    .WillOnce(Return(false));

    ON_CALL(*m_playbackController, isPlaying())
    .WillByDefault(Return(false));

    //! [THEN] seek to the element before playing it
    {
        InSequence seq;

        //! [THEN] We will seek and play selected note, but no select again
        EXPECT_CALL(*m_playbackController, seekElement(newContext.element, FLUSH_SOUND))
        .Times(1);

        std::vector<const EngravingItem*> elements = { newContext.element };
        EXPECT_CALL(*m_playbackController, playElements(elements, m_playParams, false))
        .Times(1);
    }

    std::vector<EngravingItem*> selectElements = { newContext.element };
    EXPECT_CALL(*m_interaction, select(selectElements, _, _))
    .Times(0);

    //! [WHEN] User pressed left mouse button
    m_controller->mousePressEvent(make_mousePressEvent(Qt::LeftButton, Qt::NoModifier, QPointF(100, 100)));
}

/**
 * @brief Mouse_Press_On_Selected_Text_Element
 * @details User pressed left mouse button on already selected text element
 *          We should change text cursor position
 */
TEST_F(NotationViewInputControllerTests, Mouse_Press_On_Selected_Text_Element)
{
    //! [GIVEN] There is a test score
    engraving::MasterScore* score = engraving::ScoreRW::readScore(TEST_SCORE_PATH);

    //! [GIVEN] Previous selected dynamic
    INotationInteraction::HitElementContext oldContext = hitContext(score, { ElementType::DYNAMIC });

    //! [GIVEN] User selected new dynamic that was already selected
    INotationInteraction::HitElementContext newContext = oldContext;
    newContext.element->setSelected(true);

    std::vector<EngravingItem*> selectedElements {
        newContext.element
    };

    EXPECT_CALL(*m_interaction, hitElement(_, _))
    .WillOnce(Return(newContext.element));

    EXPECT_CALL(*m_interaction, hitStaff(_))
    .WillOnce(Return(newContext.element->staff()));

    //! [GIVEN] The new hit element context with new dynamic will be set
    EXPECT_CALL(*m_interaction, setHitElementContext(newContext))
    .Times(1);

    //! [GIVEN] There isn't a range selection
    ON_CALL(*m_selection, isRange())
    .WillByDefault(Return(false));

    ON_CALL(*m_selection, elements())
    .WillByDefault(ReturnRef(selectedElements));

    //! [GIVEN] No note enter mode, no playing
    EXPECT_CALL(m_view, isNoteEnterMode())
    .WillOnce(Return(false));

    ON_CALL(*m_playbackController, isPlaying())
    .WillByDefault(Return(false));

    //! [THEN] We will seek and play selected dynamic, but no select again
    EXPECT_CALL(*m_playbackController, seekElement(newContext.element, FLUSH_SOUND))
    .Times(1);

    std::vector<const EngravingItem*> elements = { newContext.element };
    EXPECT_CALL(*m_playbackController, playElements(elements, m_playParams, false))
    .Times(0);

    std::vector<EngravingItem*> selectElements = { newContext.element };
    EXPECT_CALL(*m_interaction, select(selectElements, _, _))
    .Times(0);

    //! [GIVEN] Hit element is text element
    EXPECT_CALL(*m_interaction, isTextSelected())
    .WillOnce(Return(true));
    EXPECT_CALL(*m_interaction, isTextEditingStarted())
    .WillOnce(Return(true));

    //! [THEN] We will change text cursor position
    EXPECT_CALL(*m_interaction, changeTextCursorPosition(_))
    .Times(1);

    //! [WHEN] User pressed left mouse button
    m_controller->mousePressEvent(make_mousePressEvent(Qt::LeftButton, Qt::NoModifier, QPointF(100, 100)));
}

/**
 * @brief Mouse_Press_On_Selected_Non_Text_Element
 * @details User pressed left mouse button on already selected non text element
 *          We shouldn't change text cursor position
 */
TEST_F(NotationViewInputControllerTests, Mouse_Press_On_Selected_Non_Text_Element)
{
    //! [GIVEN] There is a test score
    engraving::MasterScore* score = engraving::ScoreRW::readScore(TEST_SCORE_PATH);

    //! [GIVEN] Previous selected hairpin
    INotationInteraction::HitElementContext oldContext = hitContext(score, { ElementType::HAIRPIN });

    //! [GIVEN] User selected new hairpin that was already selected
    INotationInteraction::HitElementContext newContext = oldContext;
    newContext.element->setSelected(true);

    std::vector<EngravingItem*> selectedElements {
        newContext.element
    };

    EXPECT_CALL(*m_interaction, hitElement(_, _))
    .WillOnce(Return(newContext.element));

    EXPECT_CALL(*m_interaction, hitStaff(_))
    .WillOnce(Return(newContext.element->staff()));

    //! [GIVEN] The new hit element context with new hairpin will be set
    EXPECT_CALL(*m_interaction, setHitElementContext(newContext))
    .Times(1);

    //! [GIVEN] There isn't a range selection
    ON_CALL(*m_selection, isRange())
    .WillByDefault(Return(false));

    ON_CALL(*m_selection, elements())
    .WillByDefault(ReturnRef(selectedElements));

    //! [GIVEN] No note enter mode, no playing
    EXPECT_CALL(m_view, isNoteEnterMode())
    .WillOnce(Return(false));

    ON_CALL(*m_playbackController, isPlaying())
    .WillByDefault(Return(false));

    //! [THEN] We will seek and play selected hairpin, but no select again
    EXPECT_CALL(*m_playbackController, seekElement(newContext.element, FLUSH_SOUND))
    .Times(1);

    std::vector<const EngravingItem*> elements = { newContext.element };
    EXPECT_CALL(*m_playbackController, playElements(elements, m_playParams, false))
    .Times(0);

    std::vector<EngravingItem*> selectElements = { newContext.element };
    EXPECT_CALL(*m_interaction, select(selectElements, _, _))
    .Times(0);

    //! [GIVEN] Hit element isn't text element
    EXPECT_CALL(*m_interaction, isTextSelected())
    .WillOnce(Return(false));

    //! [THEN] No cursor changing, no editing grips and no starting edit element because needStartEditingAfterSelecting is false
    EXPECT_CALL(*m_interaction, changeTextCursorPosition(_))
    .Times(0);
    EXPECT_CALL(*m_interaction, startEditGrip(newContext.element, _))
    .Times(0);
    EXPECT_CALL(*m_interaction, startEditElement(newContext.element))
    .Times(0);

    //! [WHEN] User pressed left mouse button
    m_controller->mousePressEvent(make_mousePressEvent(Qt::LeftButton, Qt::NoModifier, QPointF(100, 100)));
}

/**
 * @brief Mouse_Press_Range_Start_Play_From_First_Playable_Element
 * @details User selected a range in a note that is located after the previous selected note
 *          The new note should be selected and played, but no seeked
 *          The first note from a range should be seeked
 */
TEST_F(NotationViewInputControllerTests, Mouse_Press_Range_Start_Play_From_First_Playable_Element)
{
    //! [GIVEN] There is a test score
    engraving::MasterScore* score = engraving::ScoreRW::readScore(TEST_SCORE_PATH);

    //! [GIVEN] Previous selected note
    INotationInteraction::HitElementContext oldContext = hitContext(score, { ElementType::NOTE, true /*first note*/ });

    //! [GIVEN] User selected new note that is located after the previous selected note
    INotationInteraction::HitElementContext newContext = hitContext(score, { ElementType::NOTE, false /*last note*/ });

    EXPECT_CALL(*m_interaction, hitElement(_, _))
    .WillOnce(Return(newContext.element));

    EXPECT_CALL(*m_interaction, hitStaff(_))
    .WillOnce(Return(newContext.element->staff()));

    //! [THEN] The new hit element context with new note will be set
    EXPECT_CALL(*m_interaction, setHitElementContext(newContext))
    .Times(1);

    ON_CALL(*m_interaction, hitElementContext())
    .WillByDefault(ReturnRef(newContext));

    //! [GIVEN] No note enter mode, no playing
    EXPECT_CALL(m_view, isNoteEnterMode())
    .WillOnce(Return(false));

    ON_CALL(*m_playbackController, isPlaying())
    .WillByDefault(Return(false));

    //! [THEN] We will select and play selected note, but no seek
    std::vector<EngravingItem*> selectElements = { newContext.element };
    EXPECT_CALL(*m_interaction, select(selectElements, _, _))
    .Times(1)
    .WillOnce([newContext] { newContext.element->setSelected(true); });

    //! [THEN] seek to the element before playing it
    {
        InSequence seq;

        //! [THEN] We will seek first note in the range
        EXPECT_CALL(*m_playbackController, seekElement(oldContext.element, FLUSH_SOUND))
        .Times(1);

        std::vector<const EngravingItem*> playElements = { newContext.element };
        EXPECT_CALL(*m_playbackController, playElements(playElements, m_playParams, false))
        .Times(1);
    }

    EXPECT_CALL(*m_playbackController, seekElement(newContext.element, FLUSH_SOUND))
    .Times(0);

    //! [GIVEN] There is a range selection with two notes
    ON_CALL(*m_selection, isRange())
    .WillByDefault(Return(true));

    selectElements.push_back(oldContext.element);
    EXPECT_CALL(*m_selection, elements())
    .WillOnce(ReturnRef(selectElements));

    //! [WHEN] User pressed left mouse button with ShiftModifier on the new note
    m_controller->mousePressEvent(make_mousePressEvent(Qt::LeftButton, Qt::ShiftModifier, QPointF(100, 100)));
}

/**
 * @brief Mouse_Press_On_Selected_Selected_Range
 * @details User pressed left mouse button on already selected range
 *           The selection shouldn't be changed, but the first measure in the range should be seeked
 */
TEST_F(NotationViewInputControllerTests, Mouse_Press_On_Already_Selected_Range)
{
    //! [GIVEN] There is a test score
    engraving::MasterScore* score = engraving::ScoreRW::readScore(TEST_SCORE_PATH);

    //! [GIVEN] User selects a measure
    INotationInteraction::HitElementContext context = hitMeasureContext(score, 0 /*first measure*/);

    EXPECT_CALL(*m_interaction, hitElement(_, _))
    .WillOnce(Return(context.element));

    EXPECT_CALL(*m_interaction, hitStaff(_))
    .WillOnce(Return(context.staff));

    //! [THEN] The new hit element context with new measure will be set
    EXPECT_CALL(*m_interaction, setHitElementContext(context))
    .Times(1);

    ON_CALL(*m_interaction, hitElementContext())
    .WillByDefault(ReturnRef(context));

    //! [GIVEN] There is a range selection
    ON_CALL(*m_selection, isRange())
    .WillByDefault(Return(true));
    ON_CALL(*m_selectionRange, containsItem(context.element, _))
    .WillByDefault(Return(true));

    std::vector<EngravingItem*> selectElements = { context.element };
    EXPECT_CALL(*m_selection, elements())
    .WillOnce(ReturnRef(selectElements));

    //! [THEN] We should seek measure from the range
    EXPECT_CALL(*m_playbackController, seekElement(context.element, FLUSH_SOUND))
    .Times(1);

    //! [THEN] No selection change
    EXPECT_CALL(*m_interaction, select(_, _, _))
    .Times(0);

    //! [WHEN] User pressed left mouse button
    m_controller->mousePressEvent(make_mousePressEvent(Qt::LeftButton, Qt::NoModifier, QPointF(100, 100)));
}

/**
 * @brief Mouse_Press_Shift_On_Selected_Selected_Range
 * @details User pressed left mouse button with Shift on already selected range
 *          This should result in a call to `select`, to extend/diminish the selection
 */
TEST_F(NotationViewInputControllerTests, Mouse_Press_Shift_On_Already_Selected_Range)
{
    //! [GIVEN] There is a test score
    engraving::MasterScore* score = engraving::ScoreRW::readScore(TEST_SCORE_PATH);

    //! [GIVEN] User selects a measure
    INotationInteraction::HitElementContext context = hitMeasureContext(score, 0 /*first measure*/);

    EXPECT_CALL(*m_interaction, hitElement(_, _))
    .WillOnce(Return(context.element));

    EXPECT_CALL(*m_interaction, hitStaff(_))
    .WillOnce(Return(context.staff));

    //! [THEN] The new hit element context with new measure will be set
    EXPECT_CALL(*m_interaction, setHitElementContext(context))
    .Times(1);

    ON_CALL(*m_interaction, hitElementContext())
    .WillByDefault(ReturnRef(context));

    //! [GIVEN] There is a range selection
    ON_CALL(*m_selection, isRange())
    .WillByDefault(Return(true));
    ON_CALL(*m_selectionRange, containsItem(context.element, _))
    .WillByDefault(Return(true));

    //! [THEN] We should seek measure from the range
    EXPECT_CALL(*m_playbackController, seekElement(context.element, FLUSH_SOUND))
    .Times(1);

    //! [THEN] Selection is extended/diminished
    std::vector<EngravingItem*> selectElements = { context.element };
    EXPECT_CALL(*m_interaction, select(selectElements, _, _))
    .Times(1);

    EXPECT_CALL(*m_selection, elements())
    .WillOnce(ReturnRef(selectElements));

    //! [WHEN] User pressed left mouse button
    m_controller->mousePressEvent(make_mousePressEvent(Qt::LeftButton, Qt::ShiftModifier, QPointF(100, 100)));
}

/**
 * @brief Mouse_Press_On_Already_Selected_Element
 * @details User pressed on already selected note
 *          The selected note should not be selected again, but should be played and seeked
 */
TEST_F(NotationViewInputControllerTests, Mouse_Press_On_Already_Selected_Element)
{
    //! [GIVEN] There is a test score
    engraving::MasterScore* score = engraving::ScoreRW::readScore(TEST_SCORE_PATH);

    //! [GIVEN] Previous selected note
    INotationInteraction::HitElementContext oldContext = hitContext(score, { ElementType::NOTE });
    oldContext.element->setSelected(true);

    //! [GIVEN] User pressed on the previous selected note
    INotationInteraction::HitElementContext newContext = oldContext;

    EXPECT_CALL(*m_interaction, hitElement(_, _))
    .WillOnce(Return(newContext.element));

    EXPECT_CALL(*m_interaction, hitStaff(_))
    .WillOnce(Return(newContext.element->staff()));

    EXPECT_CALL(*m_interaction, setHitElementContext(newContext))
    .Times(1);

    std::vector<EngravingItem*> selectedElements = { oldContext.element };
    ON_CALL(*m_selection, elements())
    .WillByDefault(ReturnRef(selectedElements));

    //! [GIVEN] No note enter mode, no playing
    EXPECT_CALL(m_view, isNoteEnterMode())
    .WillOnce(Return(false));

    ON_CALL(*m_playbackController, isPlaying())
    .WillByDefault(Return(false));

    //! [THEN] We will no select already selected note, but play and seek
    EXPECT_CALL(*m_interaction, select(_, _, _))
    .Times(0);

    //! [THEN] seek to the element before playing it
    {
        InSequence seq;

        EXPECT_CALL(*m_playbackController, seekElement(newContext.element, FLUSH_SOUND))
        .Times(1);

        std::vector<const EngravingItem*> playElements = { newContext.element };
        EXPECT_CALL(*m_playbackController, playElements(playElements, m_playParams, false))
        .Times(1);
    }

    //! [GIVEN] There is no a range selection
    ON_CALL(*m_selection, isRange())
    .WillByDefault(Return(false));

    //! [WHEN] User pressed left mouse button with NoModifier on the new note
    m_controller->mousePressEvent(make_mousePressEvent(Qt::LeftButton, Qt::NoModifier, QPointF(100, 100)));
}

/**
 * @brief Mouse_Press_On_Range
 * @details User pressed selected new measure with ShiftModifier
 *          The new measure should be selected, shouldn't be played, previous measure should be seeked
 */
TEST_F(NotationViewInputControllerTests, Mouse_Press_On_Range)
{
    //! [GIVEN] There is a test score
    engraving::MasterScore* score = engraving::ScoreRW::readScore(TEST_SCORE_PATH);

    //! [GIVEN] Previous selected measure
    INotationInteraction::HitElementContext oldContext = hitMeasureContext(score, 0 /*first measure*/);

    //! [GIVEN] User selected new measure that is located after the previous selected measure
    INotationInteraction::HitElementContext newContext = hitMeasureContext(score, 1 /*second measure*/);
    EXPECT_CALL(*m_interaction, hitElement(_, _))
    .WillOnce(Return(newContext.element));

    EXPECT_CALL(*m_interaction, hitStaff(_))
    .WillOnce(Return(newContext.staff));

    //! [THEN] The new hit element context with new measure will be set
    EXPECT_CALL(*m_interaction, setHitElementContext(newContext))
    .Times(1);

    ON_CALL(*m_interaction, hitElementContext())
    .WillByDefault(ReturnRef(newContext));

    //! [GIVEN] No note enter mode, no playing
    EXPECT_CALL(m_view, isNoteEnterMode())
    .WillOnce(Return(false));

    ON_CALL(*m_playbackController, isPlaying())
    .WillByDefault(Return(false));

    //! [THEN] We will select new measure
    std::vector<EngravingItem*> selectElements = { newContext.element };
    EXPECT_CALL(*m_interaction, select(selectElements, _, _))
    .Times(1)
    .WillOnce([newContext] { newContext.element->setSelected(true); });

    //! [GIVEN] There is a range selection with two measures
    ON_CALL(*m_selection, isRange())
    .WillByDefault(Return(true));

    //! [THEN] No play measure
    std::vector<const EngravingItem*> playElements = { newContext.element };
    EXPECT_CALL(*m_playbackController, playElements(playElements, m_playParams, false))
    .Times(0);

    //! [THEN] Because it's a range selection, we should start playing from first measure in the range
    EXPECT_CALL(*m_playbackController, seekElement(oldContext.element, FLUSH_SOUND))
    .Times(1);

    selectElements.push_back(oldContext.element);
    EXPECT_CALL(*m_selection, elements())
    .WillOnce(ReturnRef(selectElements));

    //! [WHEN] User pressed left mouse button with ShiftModifier on the new note
    m_controller->mousePressEvent(make_mousePressEvent(Qt::LeftButton, Qt::ShiftModifier, QPointF(100, 100)));
}

/**
 * @brief Mouse_Press_On_Range_Context_Menu
 * @details The user pressed the right button on the selected measure
 *          The selection shouldn't be changed, context menu should be opened for selected measure
 */
TEST_F(NotationViewInputControllerTests, Mouse_Press_On_Range_Context_Menu)
{
    //! [GIVEN] There is a test score
    engraving::MasterScore* score = engraving::ScoreRW::readScore(TEST_SCORE_PATH);

    //! [GIVEN] User selected a measure
    INotationInteraction::HitElementContext selectMeasureContext = hitMeasureContext(score, 0 /*first measure*/);

    //! [GIVEN] User pressed the right button on the selected measure, same context
    INotationInteraction::HitElementContext contextMenuOnMeasureContext = selectMeasureContext;

    EXPECT_CALL(*m_interaction, hitElement(_, _))
    .WillOnce(Return(selectMeasureContext.element))
    //! right button click
    .WillOnce(Return(contextMenuOnMeasureContext.element));

    EXPECT_CALL(*m_interaction, hitStaff(_))
    .WillOnce(Return(selectMeasureContext.staff))
    //! right button click
    .WillOnce(Return(contextMenuOnMeasureContext.staff));

    //! [THEN] The new hit element context with new measure will be set
    EXPECT_CALL(*m_interaction, setHitElementContext(selectMeasureContext))
    .WillOnce(Return())
    //! right button click
    .WillOnce(Return());

    //! [GIVEN] No note enter mode, no playing
    EXPECT_CALL(m_view, isNoteEnterMode())
    .WillRepeatedly(Return(false));

    EXPECT_CALL(*m_playbackController, isPlaying())
    .WillRepeatedly(Return(false));

    //! [THEN] We will select new measure only one time
    std::vector<EngravingItem*> selectElements = { selectMeasureContext.element };
    EXPECT_CALL(*m_interaction, select(selectElements, _, _))
    .Times(1);

    EXPECT_CALL(*m_selection, isRange())
    .WillRepeatedly(Return(true));

    //! [GIVEN] Element is in selected range at the moment that it is selected for the second time
    EXPECT_CALL(*m_selectionRange, containsItem(contextMenuOnMeasureContext.element, _))
    .WillOnce(Return(true));

    std::vector<const EngravingItem*> playElements = { selectMeasureContext.element };
    EXPECT_CALL(*m_playbackController, playElements(playElements, m_playParams, false))
    .Times(0);

    EXPECT_CALL(*m_playbackController, seekElement(selectMeasureContext.element, FLUSH_SOUND))
    .WillOnce(Return())
    //! right button click
    .WillOnce(Return());

    //! [THEN] The selection shouldn't be changed
    EXPECT_CALL(*m_selection, elements())
    .WillRepeatedly(ReturnRef(selectElements));

#if QT_VERSION >= QT_VERSION_CHECK(6, 9, 0)
    //! Note: the context menu itself is shown by AbstractNotationPaintView::event
#else
    //! [THEN] Show context menu for measure
    EXPECT_CALL(m_view, showContextMenu(contextMenuOnMeasureContext.element->type(), _))
    .Times(1);
#endif

    //! [WHEN] User pressed left mouse button with ShiftModifier on the new measure
    m_controller->mousePressEvent(make_mousePressEvent(Qt::LeftButton, Qt::ShiftModifier, QPointF(100, 100)));

    //! [WHEN] User pressed right mouse button with NoModifier on the selected measure
    m_controller->mousePressEvent(make_mousePressEvent(Qt::RightButton, Qt::NoModifier, QPointF(100, 100)));
}

/**
 * @brief Mouse_Press_On_Range_Context_Menu_New_Selection
 * @details The user pressed the right button on the new measure
 *          The selection should be changed, context menu should be opened for new measure
 */
TEST_F(NotationViewInputControllerTests, Mouse_Press_On_Range_Context_Menu_New_Selection)
{
    //! [GIVEN] There is a test score
    engraving::MasterScore* score = engraving::ScoreRW::readScore(TEST_SCORE_PATH);

    //! [GIVEN] User selected a measure
    INotationInteraction::HitElementContext selectMeasureContext = hitMeasureContext(score, 0 /*first measure*/);

    //! [GIVEN] User pressed the right button on the selected measure, same context
    INotationInteraction::HitElementContext contextMenuOnMeasureContext = hitMeasureContext(score, 1 /*second measure*/);

    EXPECT_CALL(*m_interaction, hitElement(_, _))
    .WillOnce(Return(selectMeasureContext.element))
    //! right button click
    .WillOnce(Return(contextMenuOnMeasureContext.element));

    EXPECT_CALL(*m_interaction, hitStaff(_))
    .WillOnce(Return(selectMeasureContext.staff))
    //! right button click
    .WillOnce(Return(contextMenuOnMeasureContext.staff));

    EXPECT_CALL(*m_interaction, setHitElementContext(selectMeasureContext))
    .WillOnce(Return());
    EXPECT_CALL(*m_interaction, setHitElementContext(contextMenuOnMeasureContext))
    .WillOnce(Return());

#if QT_VERSION < QT_VERSION_CHECK(6, 9, 0)
    .WillOnce(ReturnRef(contextMenuOnMeasureContext)) // for context menu
#endif
    ;

    //! [GIVEN] No note enter mode, no playing
    EXPECT_CALL(m_view, isNoteEnterMode())
    .WillRepeatedly(Return(false));

    EXPECT_CALL(*m_playbackController, isPlaying())
    .WillRepeatedly(Return(false));

    EXPECT_CALL(*m_selection, isRange())
    .WillRepeatedly(Return(true));

    //! [THEN] The selection should be changed
    std::vector<EngravingItem*> selectElements = { selectMeasureContext.element };
    EXPECT_CALL(*m_interaction, select(selectElements, _, _))
    .Times(1);

    std::vector<EngravingItem*> contextMenuSelectElements = { contextMenuOnMeasureContext.element };
    EXPECT_CALL(*m_interaction, select(contextMenuSelectElements, _, _))
    .WillOnce(Return());

    EXPECT_CALL(*m_selection, elements())
    .WillOnce(ReturnRef(selectElements))
    .WillOnce(ReturnRef(contextMenuSelectElements));

    //! [GIVEN] New element is not in selected range at the moment that it is selected
    EXPECT_CALL(*m_selectionRange, containsItem(contextMenuOnMeasureContext.element, _))
    .WillOnce(Return(false));

    EXPECT_CALL(*m_playbackController, playElements(_, m_playParams, false))
    .Times(0);

    //! [THEN] We will seek each measures
    EXPECT_CALL(*m_playbackController, seekElement(selectMeasureContext.element, FLUSH_SOUND))
    .WillOnce(Return());

    EXPECT_CALL(*m_playbackController, seekElement(contextMenuOnMeasureContext.element, FLUSH_SOUND))
    .WillOnce(Return());

#if QT_VERSION >= QT_VERSION_CHECK(6, 9, 0)
    //! Note: the context menu itself is shown by AbstractNotationPaintView::event
#else
    //! [THEN] Show context menu for new measure
    EXPECT_CALL(m_view, showContextMenu(contextMenuOnMeasureContext.element->type(), _))
    .Times(1);
#endif

    //! [WHEN] User pressed left mouse button with ShiftModifier on the new measure
    m_controller->mousePressEvent(make_mousePressEvent(Qt::LeftButton, Qt::ShiftModifier, QPointF(100, 100)));

    //! [WHEN] User pressed right mouse button with NoModifier on the selected measure
    m_controller->mousePressEvent(make_mousePressEvent(Qt::RightButton, Qt::NoModifier, QPointF(100, 100)));
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyShortcutOverride_Disabled_DoesNotCaptureScoreViewKeys)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(false));

    QKeyEvent* ev = make_keyEvent(QEvent::ShortcutOverride, Qt::Key_S);

    bool accepted = m_controller->shortcutOverrideEvent(ev);
    EXPECT_FALSE(accepted);
    EXPECT_FALSE(ev->isAccepted());
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyShortcutOverride_Enabled_DoesNotCaptureModifiedScoreViewKeys)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(true));

    QKeyEvent* ev = make_keyEvent(QEvent::ShortcutOverride, Qt::Key_K, Qt::ControlModifier);

    bool accepted = m_controller->shortcutOverrideEvent(ev);
    EXPECT_FALSE(accepted);
    EXPECT_FALSE(ev->isAccepted());
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyInput_Enabled_CapturesBareChordOnFinalRelease)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(true));
    ON_CALL(*m_noteInput, isNoteInputMode()).WillByDefault(Return(true));

    EXPECT_CALL(*m_notationBraille, setKeys(QString("S+F"))).Times(1);

    QKeyEvent* sOverride = make_keyEvent(QEvent::ShortcutOverride, Qt::Key_S);
    bool accepted = m_controller->shortcutOverrideEvent(sOverride);
    EXPECT_TRUE(accepted);
    EXPECT_TRUE(sOverride->isAccepted());

    QKeyEvent* fOverride = make_keyEvent(QEvent::ShortcutOverride, Qt::Key_F);
    bool fAccepted = m_controller->shortcutOverrideEvent(fOverride);
    EXPECT_TRUE(fAccepted);
    EXPECT_TRUE(fOverride->isAccepted());

    QKeyEvent* sPress = make_keyEvent(QEvent::KeyPress, Qt::Key_S);
    QKeyEvent* fPress = make_keyEvent(QEvent::KeyPress, Qt::Key_F);
    m_controller->keyPressEvent(sPress);
    EXPECT_TRUE(sPress->isAccepted());
    m_controller->keyPressEvent(fPress);
    EXPECT_TRUE(fPress->isAccepted());

    QKeyEvent* sRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_S);
    QKeyEvent* fRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_F);
    m_controller->keyReleaseEvent(sRelease);
    EXPECT_TRUE(sRelease->isAccepted());
    m_controller->keyReleaseEvent(fRelease);
    EXPECT_TRUE(fRelease->isAccepted());
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyInput_Enabled_IgnoresAutoRepeatForHeldKey)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(true));
    ON_CALL(*m_noteInput, isNoteInputMode()).WillByDefault(Return(true));

    EXPECT_CALL(*m_notationBraille, setKeys(QString("D"))).Times(1);

    QKeyEvent* dPress = make_keyEvent(QEvent::KeyPress, Qt::Key_D);
    QKeyEvent* dRepeat = make_keyEvent(QEvent::KeyPress, Qt::Key_D, Qt::NoModifier, true);
    QKeyEvent* dRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_D);

    m_controller->keyPressEvent(dPress);
    EXPECT_TRUE(dPress->isAccepted());
    m_controller->keyPressEvent(dRepeat);
    EXPECT_TRUE(dRepeat->isAccepted());
    m_controller->keyReleaseEvent(dRelease);
    EXPECT_TRUE(dRelease->isAccepted());
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyInput_Enabled_ClearsPartialChordOnFocusLoss)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(true));
    ON_CALL(*m_noteInput, isNoteInputMode()).WillByDefault(Return(true));

    EXPECT_CALL(*m_notationBraille, setKeys(_)).Times(0);

    QKeyEvent* sPress = make_keyEvent(QEvent::KeyPress, Qt::Key_S);
    m_controller->keyPressEvent(sPress);

    m_controller->focusChanged(false);

    QKeyEvent* sRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_S);
    m_controller->keyReleaseEvent(sRelease);
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyShortcutOverride_Enabled_DoesNotCaptureWhileTextEditing)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(true));

    EXPECT_CALL(*m_interaction, isTextEditingStarted()).WillOnce(Return(true));

    QKeyEvent* ev = make_keyEvent(QEvent::ShortcutOverride, Qt::Key_L);

    bool accepted = m_controller->shortcutOverrideEvent(ev);
    EXPECT_FALSE(accepted);
    EXPECT_FALSE(ev->isAccepted());
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyInput_ModifiedTrackedRelease_ClearsStateNoDispatch)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(true));
    ON_CALL(*m_noteInput, isNoteInputMode()).WillByDefault(Return(true));

    EXPECT_CALL(*m_notationBraille, setKeys(_)).Times(0);

    QKeyEvent* sPress = make_keyEvent(QEvent::KeyPress, Qt::Key_S);
    m_controller->keyPressEvent(sPress);
    EXPECT_TRUE(sPress->isAccepted());

    QKeyEvent* sRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_S, Qt::ShiftModifier);
    m_controller->keyReleaseEvent(sRelease);
    EXPECT_TRUE(sRelease->isAccepted());

    EXPECT_CALL(*m_notationBraille, setKeys(QString("J"))).Times(1);

    QKeyEvent* jOverride = make_keyEvent(QEvent::ShortcutOverride, Qt::Key_J);
    m_controller->shortcutOverrideEvent(jOverride);

    QKeyEvent* jPress = make_keyEvent(QEvent::KeyPress, Qt::Key_J);
    m_controller->keyPressEvent(jPress);

    QKeyEvent* jRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_J);
    m_controller->keyReleaseEvent(jRelease);
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyInput_ModifiedShortcutDuringPartialChord_ClearsStateNoDispatch)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(true));
    ON_CALL(*m_noteInput, isNoteInputMode()).WillByDefault(Return(true));

    EXPECT_CALL(*m_notationBraille, setKeys(_)).Times(0);

    QKeyEvent* sPress = make_keyEvent(QEvent::KeyPress, Qt::Key_S);
    m_controller->keyPressEvent(sPress);
    EXPECT_TRUE(sPress->isAccepted());

    QKeyEvent* modifiedShortcut = make_keyEvent(QEvent::ShortcutOverride, Qt::Key_K, Qt::ControlModifier);
    bool accepted = m_controller->shortcutOverrideEvent(modifiedShortcut);
    EXPECT_FALSE(accepted);
    EXPECT_FALSE(modifiedShortcut->isAccepted());

    QKeyEvent* kRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_K);
    m_controller->keyReleaseEvent(kRelease);
    EXPECT_TRUE(kRelease->isAccepted());

    QKeyEvent* sRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_S);
    m_controller->keyReleaseEvent(sRelease);
    EXPECT_TRUE(sRelease->isAccepted());
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyInput_NonBrailleKeyPressDuringPartialChord_ClearsStateNoDispatch)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(true));
    ON_CALL(*m_noteInput, isNoteInputMode()).WillByDefault(Return(true));

    EXPECT_CALL(*m_notationBraille, setKeys(_)).Times(0);

    QKeyEvent* sPress = make_keyEvent(QEvent::KeyPress, Qt::Key_S);
    m_controller->keyPressEvent(sPress);
    EXPECT_TRUE(sPress->isAccepted());

    QKeyEvent* aPress = make_keyEvent(QEvent::KeyPress, Qt::Key_A);
    m_controller->keyPressEvent(aPress);

    QKeyEvent* sRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_S);
    m_controller->keyReleaseEvent(sRelease);
    EXPECT_TRUE(sRelease->isAccepted());
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyInput_InactiveAutoRepeatRelease_AcceptsNonMutating)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(true));
    ON_CALL(*m_noteInput, isNoteInputMode()).WillByDefault(Return(true));

    EXPECT_CALL(*m_notationBraille, setKeys(_)).Times(0);

    QKeyEvent* sPress = make_keyEvent(QEvent::KeyPress, Qt::Key_S);
    m_controller->keyPressEvent(sPress);
    EXPECT_TRUE(sPress->isAccepted());

    ON_CALL(*m_interaction, isTextEditingStarted()).WillByDefault(Return(true));

    QKeyEvent* sAutoRepeatRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_S, Qt::NoModifier, true);
    m_controller->keyReleaseEvent(sAutoRepeatRelease);
    EXPECT_TRUE(sAutoRepeatRelease->isAccepted());

    QKeyEvent* sRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_S);
    m_controller->keyReleaseEvent(sRelease);
    EXPECT_TRUE(sRelease->isAccepted());
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyShortcutOverride_Enabled_DoesNotCaptureWhileEditingElement)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(true));

    QKeyEvent* ev = make_keyEvent(QEvent::ShortcutOverride, Qt::Key_J);

    EXPECT_CALL(*m_interaction, isTextEditingStarted()).WillOnce(Return(false));
    EXPECT_CALL(*m_interaction, isEditingElement()).Times(2).WillRepeatedly(Return(true));
    EXPECT_CALL(*m_interaction, isEditAllowed(ev)).WillOnce(Return(false));

    bool accepted = m_controller->shortcutOverrideEvent(ev);
    EXPECT_FALSE(accepted);
    EXPECT_FALSE(ev->isAccepted());
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyInput_Enabled_StartsNoteInputBeforeDispatchingChord)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(true));

    {
        InSequence seq;
        EXPECT_CALL(*m_noteInput, isNoteInputMode()).WillOnce(Return(false));
        EXPECT_CALL(*m_noteInput, startNoteInput(NoteInputMethod::BY_NOTE_NAME, false)).Times(1);
        EXPECT_CALL(*m_noteInput, isNoteInputMode()).WillOnce(Return(true));
        EXPECT_CALL(*m_notationBraille, setKeys(QString("J"))).Times(1);
    }

    QKeyEvent* jPress = make_keyEvent(QEvent::KeyPress, Qt::Key_J);
    m_controller->keyPressEvent(jPress);

    QKeyEvent* jRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_J);
    m_controller->keyReleaseEvent(jRelease);
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyInput_Enabled_EntersBrailleInputModeBeforeDispatchingChord)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(true));
    ON_CALL(*m_noteInput, isNoteInputMode()).WillByDefault(Return(true));
    ON_CALL(*m_notationBraille, isBrailleInputMode()).WillByDefault(Return(false));

    {
        InSequence seq;
        EXPECT_CALL(*m_notationBraille, setMode(BrailleMode::BrailleInput)).Times(1);
        EXPECT_CALL(*m_notationBraille, setKeys(QString("F"))).Times(1);
    }

    QKeyEvent* fPress = make_keyEvent(QEvent::KeyPress, Qt::Key_F);
    m_controller->keyPressEvent(fPress);

    QKeyEvent* fRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_F);
    m_controller->keyReleaseEvent(fRelease);
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyInput_NonBrailleKeyPress_ClearsPendingInputAndPassesThrough)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(true));

    EXPECT_CALL(*m_notationBraille, clearPendingInput()).Times(1);
    EXPECT_CALL(*m_notationBraille, setKeys(_)).Times(0);

    QKeyEvent* aPress = make_keyEvent(QEvent::KeyPress, Qt::Key_A);
    m_controller->keyPressEvent(aPress);

    EXPECT_FALSE(aPress->isAccepted());
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyInput_ModifiedSixKeyShortcut_ClearsPendingInputAndPassesThrough)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(true));

    EXPECT_CALL(*m_notationBraille, clearPendingInput()).Times(1);
    EXPECT_CALL(*m_notationBraille, setKeys(_)).Times(0);

    QKeyEvent* modifiedShortcut = make_keyEvent(QEvent::ShortcutOverride, Qt::Key_K, Qt::ControlModifier);
    bool accepted = m_controller->shortcutOverrideEvent(modifiedShortcut);

    EXPECT_FALSE(accepted);
    EXPECT_FALSE(modifiedShortcut->isAccepted());
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyInput_InterleavedShortcutOverrideAndPress_KeepsChord)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(true));
    ON_CALL(*m_noteInput, isNoteInputMode()).WillByDefault(Return(true));
    ON_CALL(*m_notationBraille, isBrailleInputMode()).WillByDefault(Return(true));

    EXPECT_CALL(*m_notationBraille, clearPendingInput()).Times(0);
    EXPECT_CALL(*m_notationBraille, setKeys(QString("S+F"))).Times(1);

    QKeyEvent* sOverride = make_keyEvent(QEvent::ShortcutOverride, Qt::Key_S);
    m_controller->shortcutOverrideEvent(sOverride);

    QKeyEvent* sPress = make_keyEvent(QEvent::KeyPress, Qt::Key_S);
    m_controller->keyPressEvent(sPress);

    QKeyEvent* fOverride = make_keyEvent(QEvent::ShortcutOverride, Qt::Key_F);
    m_controller->shortcutOverrideEvent(fOverride);

    QKeyEvent* fPress = make_keyEvent(QEvent::KeyPress, Qt::Key_F);
    m_controller->keyPressEvent(fPress);

    QKeyEvent* sRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_S);
    m_controller->keyReleaseEvent(sRelease);

    QKeyEvent* fRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_F);
    m_controller->keyReleaseEvent(fRelease);
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyInput_ContextLostBeforeRelease_ClearsState)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(true));
    ON_CALL(*m_noteInput, isNoteInputMode()).WillByDefault(Return(true));

    EXPECT_CALL(*m_notationBraille, setKeys(_)).Times(0);

    QKeyEvent* sOverride = make_keyEvent(QEvent::ShortcutOverride, Qt::Key_S);
    m_controller->shortcutOverrideEvent(sOverride);

    QKeyEvent* sPress = make_keyEvent(QEvent::KeyPress, Qt::Key_S);
    m_controller->keyPressEvent(sPress);
    EXPECT_TRUE(sPress->isAccepted());

    ON_CALL(*m_interaction, isTextEditingStarted()).WillByDefault(Return(true));

    QKeyEvent* sRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_S);
    m_controller->keyReleaseEvent(sRelease);
    EXPECT_TRUE(sRelease->isAccepted());

    ON_CALL(*m_interaction, isTextEditingStarted()).WillByDefault(Return(false));

    EXPECT_CALL(*m_notationBraille, setKeys(QString("J"))).Times(1);

    QKeyEvent* jOverride = make_keyEvent(QEvent::ShortcutOverride, Qt::Key_J);
    m_controller->shortcutOverrideEvent(jOverride);

    QKeyEvent* jPress = make_keyEvent(QEvent::KeyPress, Qt::Key_J);
    m_controller->keyPressEvent(jPress);

    QKeyEvent* jRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_J);
    m_controller->keyReleaseEvent(jRelease);
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyInput_ContextLossDuringChord_ClearsStateBeforeRelease)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(true));
    ON_CALL(*m_noteInput, isNoteInputMode()).WillByDefault(Return(true));

    QKeyEvent* sOverride = make_keyEvent(QEvent::ShortcutOverride, Qt::Key_S);
    m_controller->shortcutOverrideEvent(sOverride);

    QKeyEvent* sPress = make_keyEvent(QEvent::KeyPress, Qt::Key_S);
    m_controller->keyPressEvent(sPress);
    EXPECT_TRUE(sPress->isAccepted());

    ON_CALL(*m_interaction, isTextEditingStarted()).WillByDefault(Return(true));

    QKeyEvent* sRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_S);
    m_controller->keyReleaseEvent(sRelease);
    EXPECT_TRUE(sRelease->isAccepted());

    ON_CALL(*m_interaction, isTextEditingStarted()).WillByDefault(Return(false));

    EXPECT_CALL(*m_notationBraille, setKeys(_)).Times(0);

    QKeyEvent* sReleaseAgain = make_keyEvent(QEvent::KeyRelease, Qt::Key_S);
    m_controller->keyReleaseEvent(sReleaseAgain);
    EXPECT_TRUE(sReleaseAgain->isAccepted());

    EXPECT_CALL(*m_notationBraille, setKeys(QString("J"))).Times(1);

    QKeyEvent* jOverride = make_keyEvent(QEvent::ShortcutOverride, Qt::Key_J);
    m_controller->shortcutOverrideEvent(jOverride);

    QKeyEvent* jPress = make_keyEvent(QEvent::KeyPress, Qt::Key_J);
    m_controller->keyPressEvent(jPress);

    QKeyEvent* jRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_J);
    m_controller->keyReleaseEvent(jRelease);
}

TEST_F(NotationViewInputControllerTests, BrailleSixKeyInput_ClearInputBuffer_ClearsPendingInputAndPartialChord)
{
    ON_CALL(*m_brailleConfiguration, sixKeyInputEnabled()).WillByDefault(Return(true));
    ON_CALL(*m_noteInput, isNoteInputMode()).WillByDefault(Return(true));

    QKeyEvent* sPress = make_keyEvent(QEvent::KeyPress, Qt::Key_S);
    m_controller->keyPressEvent(sPress);
    EXPECT_TRUE(sPress->isAccepted());

    EXPECT_CALL(*m_notationBraille, clearPendingInput()).Times(1);
    EXPECT_CALL(*m_notationBraille, setKeys(_)).Times(0);

    m_controller->clearBrailleInputBuffer();

    QKeyEvent* sRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_S);
    m_controller->keyReleaseEvent(sRelease);
    EXPECT_TRUE(sRelease->isAccepted());

    Mock::VerifyAndClearExpectations(m_notationBraille.get());

    EXPECT_CALL(*m_notationBraille, setKeys(QString("J"))).Times(1);

    QKeyEvent* jPress = make_keyEvent(QEvent::KeyPress, Qt::Key_J);
    m_controller->keyPressEvent(jPress);

    QKeyEvent* jRelease = make_keyEvent(QEvent::KeyRelease, Qt::Key_J);
    m_controller->keyReleaseEvent(jRelease);
}
TEST_F(NotationViewInputControllerTests, BrailleConfigurationMock_AdvanceCursorAfterDot_DefaultsToFalse)
{
    EXPECT_CALL(*m_brailleConfiguration, advanceCursorAfterDot())
        .WillOnce(Return(false));
    EXPECT_FALSE(m_brailleConfiguration->advanceCursorAfterDot());
}
 
TEST_F(NotationViewInputControllerTests, BrailleConfigurationMock_AdvanceCursorAfterDot_CanBeEnabled)
{
    EXPECT_CALL(*m_brailleConfiguration, advanceCursorAfterDot())
        .WillOnce(Return(true));
    EXPECT_TRUE(m_brailleConfiguration->advanceCursorAfterDot());
}
 
TEST_F(NotationViewInputControllerTests, NotationNoteInputMock_AdvanceCursor_IsCallable)
{
    EXPECT_CALL(*m_noteInput, advanceCursor()).Times(1);
    m_noteInput->advanceCursor();
}
