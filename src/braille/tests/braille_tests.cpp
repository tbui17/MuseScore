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

#include <gtest/gtest.h>

#include <memory>
#include <vector>

#include <QFile>

#include "engraving/tests/utils/scorerw.h"
#include "engraving/tests/utils/scorecomp.h"

#include "engraving/dom/chord.h"
#include "engraving/dom/masterscore.h"
#include "engraving/dom/measure.h"
#include "engraving/dom/note.h"
#include "engraving/dom/segment.h"
#include "../internal/braille.h"
#include "../internal/brailleconfiguration.h"
#include "../internal/brailleinput.h"

#define private public
#include "../internal/notationbraille.h"
#undef private

using namespace mu::engraving;

static const String BRAILLE_DIR(u"data/");

class Braille_Tests : public ::testing::Test
{
public:
    void brailleSaveTest(const char* file);
};

//---------------------------------------------------------
//   fixupScore -- do required fixups after reading/importing score
//---------------------------------------------------------

static void fixupScore(MasterScore* score)
{
    score->connectTies();
    score->masterScore()->rebuildMidiMapping();
}

static bool saveBraille(MasterScore* score, const String& saveName)
{
    QFile file(saveName);
    if (!file.open(QIODevice::WriteOnly)) {
        return false;
    }

    bool res = Braille(score).write(file);
    file.close();
    return res;
}

static bool saveCompareBrailleScore(MasterScore* score, const String& saveName, const String& compareWithLocalPath)
{
    EXPECT_TRUE(saveBraille(score, saveName));
    return ScoreComp::compareFiles(saveName,  ScoreRW::rootPath() + u"/" + compareWithLocalPath);
}

static std::vector<Note*> firstNotes(MasterScore* score, size_t count)
{
    std::vector<Note*> result;

    for (Segment* segment = score->firstSegment(SegmentType::ChordRest); segment && result.size() < count;
         segment = segment->next1(SegmentType::ChordRest)) {
        ChordRest* chordRest = segment->nextChordRest(0);
        if (!chordRest || !chordRest->isChord()) {
            continue;
        }

        const std::vector<Note*>& notes = toChord(chordRest)->notes();
        if (!notes.empty()) {
            result.push_back(notes.front());
        }
    }

    return result;
}

void Braille_Tests::brailleSaveTest(const char* file)
{
    String fileName = String::fromUtf8(file);
    MasterScore* score = ScoreRW::readScore(BRAILLE_DIR + fileName + u".mscx", false);
    EXPECT_TRUE(score);
    fixupScore(score);
    score->doLayout();
    EXPECT_TRUE(saveCompareBrailleScore(score, fileName + ".brf", BRAILLE_DIR + fileName + "_ref.brf"));
    delete score;
}

TEST_F(Braille_Tests, pitches) {
    brailleSaveTest("testPitches");
}
TEST_F(Braille_Tests, octaveMarks) {
    brailleSaveTest("testOctaveMarks");
}
TEST_F(Braille_Tests, tempo1) {
    brailleSaveTest("testTempo_Example_1.8.1.1_MBC2015");
}
TEST_F(Braille_Tests, tempo2) {
    brailleSaveTest("testTempo_Example_1.8.1.2_MBC2015");
}
TEST_F(Braille_Tests, sectionalBarline) {
    brailleSaveTest("testBarline_Example_1.10.3.2_MBC2015");
}
TEST_F(Braille_Tests, specialBarline) {
    brailleSaveTest("testBarline_Example_1.10.1.1_MBC2015");
}
TEST_F(Braille_Tests, notes) {
    brailleSaveTest("testNotes_Example_2.1_MBC2015");
}
TEST_F(Braille_Tests, octavesNoChords) {
    // TODO a,b,c section names not exported
    brailleSaveTest("testOctavesNoChords_Example_3.2.2.1_MBC2015");
}
TEST_F(Braille_Tests, clefs) {
    brailleSaveTest("testClefs_Example_4.2_MBC2015");
}
TEST_F(Braille_Tests, mmrests) {
    brailleSaveTest("testMMRests_Example_5.3.1_MBC2015");
}
TEST_F(Braille_Tests, accidentals) {
    brailleSaveTest("testAccidentals_Example_6.1_MBC2015");
}
TEST_F(Braille_Tests, quarterAccidentals) {
    brailleSaveTest("testQToneAccidentals_Example_6.3_MBC2015");
}
TEST_F(Braille_Tests, keySigs) {
    // a bit changed. the second key sig does not have naturals
    brailleSaveTest("testKeySig_Example_6.5_MBC2015");
}
TEST_F(Braille_Tests, timeSignature) {
    brailleSaveTest("testTimeSig_Example_7.1_MBC2015");
}
TEST_F(Braille_Tests, chords1) {
    brailleSaveTest("testChords_Example_9.1.MBC2015");
}
TEST_F(Braille_Tests, chords2) {
// TODO 9.1.1.d octave mark in unison intervals
    brailleSaveTest("testChords_Example_9.1.1_MBC2015");
}
TEST_F(Braille_Tests, chords3) {
    brailleSaveTest("testChords_Example_9.2.1_MBC2015");
}
TEST_F(Braille_Tests, chords4) {
    brailleSaveTest("testChords_Example_9.2.2_MBC2015");
}
TEST_F(Braille_Tests, ties1) {
    brailleSaveTest("testTie");
}
TEST_F(Braille_Tests, ties2) {
    brailleSaveTest("testTie_Example_10.1_MBC2015");
}
TEST_F(Braille_Tests, tiesChords1) {
    brailleSaveTest("testTie_Example_10.2.1_MBC2015");
}
TEST_F(Braille_Tests, tiesChords2) {
    brailleSaveTest("testTie_Example_10.2.2_MBC2015");
}
TEST_F(Braille_Tests, tiesChords3) {
    brailleSaveTest("testTie_Example_10.2.3_MBC2015");
}
TEST_F(Braille_Tests, voices1) {
    brailleSaveTest("testVoices_Example_11.1.1.1_MBC2015");
}
TEST_F(Braille_Tests, voices2) {
    brailleSaveTest("testVoices_Example_11.1.1.2_MBC2015");
}
TEST_F(Braille_Tests, voices3) {
    brailleSaveTest("testVoices_Example_11.1.1.3_MBC2015");
}
TEST_F(Braille_Tests, voices4) {
    brailleSaveTest("testVoices_Example_11.1.1.4_MBC2015");
}
TEST_F(Braille_Tests, voices5) {
    brailleSaveTest("testVoices_Example_11.1.4.1_MBC2015");
}
TEST_F(Braille_Tests, slursShort) {
    brailleSaveTest("testSlur_Example_13.2_MBC2015");
}
TEST_F(Braille_Tests, slursLong) {
    brailleSaveTest("testSlur_Example_13.3.b_MBC2015");
}
TEST_F(Braille_Tests, slursWithRest) {
    // the Braille ref does not use part measure repeats
    brailleSaveTest("testSlur_Example_13.3.2_MBC2015");
}
TEST_F(Braille_Tests, slursLayered) {
    // the Braille ref uses bracket slurs even if layered instead of doubled-slur
    brailleSaveTest("testSlur_Example_13.3.3_MBC2015");
}
TEST_F(Braille_Tests, slursShortConvergence) {
    brailleSaveTest("testSlur_Example_13.4.1_MBC2015");
}
TEST_F(Braille_Tests, slursMixConvergence) {
    brailleSaveTest("testSlur_Example_13.4.2_b_MBC2015");
}
TEST_F(Braille_Tests, slursMixAndTies) {
    brailleSaveTest("testSlur_Example_13.5.1_b_MBC2015");
}
TEST_F(Braille_Tests, tremolo) {
    brailleSaveTest("testTremolo_Example_14.2.1_MBC2015");
}
TEST_F(Braille_Tests, tremoloAlt) {
    brailleSaveTest("testTremoloAlt_Example_14.3.1_MBC2015");
}
TEST_F(Braille_Tests, fingering1) {
    brailleSaveTest("testFingering_Example_15.1.1_MBC2015");
}
TEST_F(Braille_Tests, fingering2) {
    brailleSaveTest("testFingering_Example_15.2.1_MBC2015");
}
TEST_F(Braille_Tests, graceNotes) {
    // TODO: last measure with doubling grace mark for >4 grace notes
    brailleSaveTest("testGrace_Example_16.2.1_MBC2015");
}
TEST_F(Braille_Tests, graceChords) {
    brailleSaveTest("testGrace_Example_16.2.1.1_MBC2015");
}
TEST_F(Braille_Tests, ornaments) {
    brailleSaveTest("testOrnaments_Example_16.5_MBC2015");
}
TEST_F(Braille_Tests, glissando) {
    brailleSaveTest("testGlissando_Example_16.6.1_MBC2015");
}
TEST_F(Braille_Tests, repeats) {
    brailleSaveTest("testRepeats_Example_17.1.1_MBC2015");
}
TEST_F(Braille_Tests, voltas1) {
    brailleSaveTest("testVolta_Example_17.1.1.1_MBC2015");
}
TEST_F(Braille_Tests, voltas2) {
    brailleSaveTest("testVolta_Example_17.1.1.2_MBC2015");
}
TEST_F(Braille_Tests, voltas3) {
    brailleSaveTest("testVolta_Example_17.1.1.3_MBC2015");
}
TEST_F(Braille_Tests, testMarkersJumps) {
    brailleSaveTest("testJumps_Example_20.2.1_MBC2015");
}
TEST_F(Braille_Tests, breath) {
    brailleSaveTest("testBreaths_Example_22.2.1_MBC2015");
}
TEST_F(Braille_Tests, articulations) {
    brailleSaveTest("testArticulations_Example_22.1_MBC2015");
}
TEST_F(Braille_Tests, hairpins) {
    // removed the 4th measure from the example as MuseScore does not have a representations for mordents with accidentals
    brailleSaveTest("testHairpins_Example_22.3.3.2_MBC2015");
}
TEST_F(Braille_Tests, sectionBreak) {
    brailleSaveTest("testSectionBreak");
}

TEST_F(Braille_Tests, shortSlurToEarlierNoteIsIgnored)
{
    std::unique_ptr<MasterScore> score(ScoreRW::readScore(BRAILLE_DIR + u"testPitches.mscx", false));
    ASSERT_TRUE(score);
    fixupScore(score.get());
    score->doLayout();

    std::vector<Note*> notes = firstNotes(score.get(), 2);
    ASSERT_EQ(notes.size(), 2);

    auto iocCtx = std::make_shared<muse::modularity::Context>(1);
    NotationBraille notationBraille(iocCtx);
    notationBraille.brailleInput()->setSlurStartNote(notes[1]);
    notationBraille.current_engraving_item = notes[0];

    EXPECT_FALSE(notationBraille.addSlur());
    EXPECT_EQ(notationBraille.brailleInput()->slurStartNote(), nullptr);
}

TEST_F(Braille_Tests, longSlurToEarlierNoteIsIgnored)
{
    std::unique_ptr<MasterScore> score(ScoreRW::readScore(BRAILLE_DIR + u"testPitches.mscx", false));
    ASSERT_TRUE(score);
    fixupScore(score.get());
    score->doLayout();

    std::vector<Note*> notes = firstNotes(score.get(), 2);
    ASSERT_EQ(notes.size(), 2);

    auto iocCtx = std::make_shared<muse::modularity::Context>(1);
    NotationBraille notationBraille(iocCtx);
    notationBraille.brailleInput()->setLongSlurStartNote(notes[1]);
    notationBraille.current_engraving_item = notes[0];

    EXPECT_FALSE(notationBraille.addLongSlur());
    EXPECT_EQ(notationBraille.brailleInput()->longSlurStartNote(), nullptr);
}

TEST_F(Braille_Tests, tieToEarlierNoteIsIgnored)
{
    std::unique_ptr<MasterScore> score(ScoreRW::readScore(BRAILLE_DIR + u"testPitches.mscx", false));
    ASSERT_TRUE(score);
    fixupScore(score.get());
    score->doLayout();

    std::vector<Note*> notes = firstNotes(score.get(), 2);
    ASSERT_EQ(notes.size(), 2);

    auto iocCtx = std::make_shared<muse::modularity::Context>(1);
    NotationBraille notationBraille(iocCtx);
    notationBraille.brailleInput()->setTieStartNote(notes[1]);
    notationBraille.current_engraving_item = notes[0];

    EXPECT_FALSE(notationBraille.addTie());
    EXPECT_EQ(notationBraille.brailleInput()->tieStartNote(), nullptr);
}

TEST(BrailleInputStateTests, hasPendingInputReflectsBufferContents)
{
    BrailleInputState state;

    EXPECT_FALSE(state.hasPendingInput());

    state.insertToBuffer("5");
    EXPECT_TRUE(state.hasPendingInput());

    state.resetBuffer();
    EXPECT_FALSE(state.hasPendingInput());
}

TEST(BrailleInputStateTests, hasPendingInputIncludesTupletIndicator)
{
    BrailleInputState state;

    state.setTupletIndicator(true);
    EXPECT_TRUE(state.hasPendingInput());

    state.reset();
    EXPECT_FALSE(state.hasPendingInput());
}

TEST(BrailleInputStateTests, initializeClearsPendingTupletIndicator)
{
    BrailleInputState state;

    state.setTupletIndicator(true);
    state.insertToBuffer("5");

    state.initialize();

    EXPECT_FALSE(state.hasPendingInput());
    EXPECT_FALSE(state.tupletIndicator());
}

TEST(BrailleInputStateTests, removeLastInputCellRemovesOnlyTheLastCell)
{
    BrailleInputState state;

    state.insertToBuffer("5");
    state.insertToBuffer("1456");
    state.insertToBuffer("3");

    EXPECT_EQ(state.buffer(), "5-1456-3");
    EXPECT_TRUE(state.removeLastInputCell());
    EXPECT_EQ(state.buffer(), "5-1456");
    EXPECT_TRUE(state.removeLastInputCell());
    EXPECT_EQ(state.buffer(), "5");
    EXPECT_TRUE(state.removeLastInputCell());
    EXPECT_EQ(state.buffer(), "");
    EXPECT_FALSE(state.hasPendingInput());
    EXPECT_FALSE(state.removeLastInputCell());
}

TEST_F(Braille_Tests, clearPendingInputResetsInputBuffer)
{
    NotationBraille notationBraille(std::make_shared<muse::modularity::Context>(1));

    notationBraille.brailleInput()->insertToBuffer("1");
    ASSERT_TRUE(notationBraille.brailleInput()->hasPendingInput());

    notationBraille.clearPendingInput();

    EXPECT_FALSE(notationBraille.brailleInput()->hasPendingInput());
}

TEST(BrailleConfigurationTests, sixKeyInputEnabledDefaultsToFalseAndCanBeChanged)
{
    BrailleConfiguration configuration;
    configuration.init();

    EXPECT_FALSE(configuration.sixKeyInputEnabled());

    configuration.setSixKeyInputEnabled(true);
    EXPECT_TRUE(configuration.sixKeyInputEnabled());

    configuration.setSixKeyInputEnabled(false);
    EXPECT_FALSE(configuration.sixKeyInputEnabled());
}
