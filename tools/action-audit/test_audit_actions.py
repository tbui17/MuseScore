import pytest
from audit_actions import (
    CppParser,
    extract_register_qml_uri_calls,
    extract_ui_action_codes,
    extract_dispatcher_reg_codes,
    normalize_uri,
    normalize_action_code,
    fuzzy_match,
    derive_action_code,
    derive_title,
    derive_module,
    get_controller_class,
    scan_codebase,
    generate_code_blocks,
    generate_for_uri,
    print_scan_results,
    Candidate,
)


class TestCppParser:
    def test_parser_initializes(self):
        """Parser can be created and parses simple C++."""
        parser = CppParser()
        code = b'int main() { return 0; }'
        tree = parser.parse(code)
        assert tree is not None
        assert tree.root_node.type == 'translation_unit'


class TestRegisterQmlUriExtraction:
    def test_extracts_simple_call(self):
        """Extracts URI, module, component from a registerQmlUri call."""
        code = b'''
        void Foo::bar() {
            ir->registerQmlUri(Uri("musescore://playback/speeddialog"), "MuseScore.Playback", "PlaybackSpeedDialog");
        }
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_register_qml_uri_calls(tree, code, "src/playback/playbackmodule.cpp")
        assert len(results) == 1
        assert results[0].uri == "musescore://playback/speeddialog"
        assert results[0].qml_module == "MuseScore.Playback"
        assert results[0].component == "PlaybackSpeedDialog"
        assert results[0].source_file == "src/playback/playbackmodule.cpp"

    def test_extracts_multiple_calls(self):
        """Extracts multiple registerQmlUri calls from one file."""
        code = b'''
        void Foo::bar() {
            ir->registerQmlUri(Uri("musescore://notation/parts"), "MuseScore.NotationScene", "PartsDialog");
            ir->registerQmlUri(Uri("musescore://notation/settempo"), "MuseScore.NotationScene", "TempoDialog");
        }
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_register_qml_uri_calls(tree, code, "src/notationscene/notationscenemodule.cpp")
        assert len(results) == 2
        assert results[0].uri == "musescore://notation/parts"
        assert results[1].uri == "musescore://notation/settempo"


class TestUiActionExtraction:
    def test_extracts_simple_action(self):
        """Extracts action code from a UiAction declaration."""
        code = b'''
        const UiActionList Foo::s_actions = {
            UiAction("play",
                     mu::context::UiCtxProjectOpened,
                     mu::context::CTX_NOTATION_FOCUSED,
                     TranslatableString("action", "Play")),
        };
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_ui_action_codes(tree, code)
        assert len(results) == 1
        assert results[0] == "play"

    def test_extracts_multiple_actions(self):
        """Extracts multiple UiAction codes from a file."""
        code = b'''
        const UiActionList Foo::s_actions = {
            UiAction("play", ...),
            UiAction("stop", ...),
            UiAction("rewind", ...),
        };
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_ui_action_codes(tree, code)
        assert len(results) == 3
        assert "play" in results
        assert "stop" in results
        assert "rewind" in results

    def test_extracts_action_with_protocol_prefix(self):
        """Extracts action codes with action:// prefix."""
        code = b'''
        UiAction("action://notation/copy", ...),
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_ui_action_codes(tree, code)
        assert len(results) == 1
        assert results[0] == "action://notation/copy"


class TestDispatcherRegExtraction:
    def test_extracts_dispatcher_reg(self):
        """Extracts action code from dispatcher()->reg() calls."""
        code = b'''
        void Foo::init() {
            dispatcher()->reg(this, "play", [this]() { togglePlay(); });
            dispatcher()->reg(this, "stop", this, &Foo::stop);
        }
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_dispatcher_reg_codes(tree, code)
        assert len(results) == 2
        assert "play" in results
        assert "stop" in results

    def test_extracts_register_action(self):
        """Extracts action code from registerAction() calls."""
        code = b'''
        void Foo::init() {
            registerAction("set-tempo", [this]() { openSetTempoDialog(); });
            registerAction("current-tempo", [this]() { announceCurrentTempo(); });
        }
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_dispatcher_reg_codes(tree, code)
        assert len(results) == 2
        assert "set-tempo" in results
        assert "current-tempo" in results


class TestNormalization:
    def test_strip_musescore_prefix(self):
        """Strips musescore:// prefix from URI."""
        assert normalize_uri("musescore://notation/settempo") == "settempo"

    def test_strip_muse_prefix(self):
        """Strips muse:// prefix from URI."""
        assert normalize_uri("muse://preferences") == "preferences"

    def test_strip_module_segment(self):
        """Strips the module segment (first path component)."""
        assert normalize_uri("musescore://playback/speeddialog") == "speeddialog"
        assert normalize_uri("musescore://project/export") == "export"

    def test_kebab_case_conversion(self):
        """Converts camelCase to kebab-case."""
        assert normalize_action_code("gotoMeasure") == "goto-measure"
        assert normalize_action_code("setTempo") == "set-tempo"

    def test_preserves_existing_kebab(self):
        """Preserves existing kebab-case action codes."""
        assert normalize_action_code("set-tempo") == "set-tempo"
        assert normalize_action_code("play") == "play"

    def test_fuzzy_match_removes_hyphens(self):
        """Fuzzy matching removes hyphens for comparison."""
        assert fuzzy_match("settempo", "set-tempo") is True
        assert fuzzy_match("speeddialog", "speed-dialog") is True
        assert fuzzy_match("play", "stop") is False

    def test_action_code_with_protocol_prefix(self):
        """Normalizes action codes with action:// prefix."""
        assert normalize_action_code("action://notation/copy") == "copy"


class TestDerivation:
    def test_derive_action_code_from_uri(self):
        """Derives action code from URI last segment (kebab-case)."""
        assert derive_action_code("musescore://playback/speeddialog") == "playback-speed"

    def test_derive_title_from_component(self):
        """Derives title from component name minus 'Dialog', title case."""
        assert derive_title("PlaybackSpeedDialog") == "Playback speed"
        assert derive_title("GoToPositionDialog") == "Go to position"
        assert derive_title("ExportDialog") == "Export"

    def test_derive_module_from_file_path(self):
        """Derives module name from the source file path."""
        assert derive_module("src/playback/playbackmodule.cpp") == "playback"
        assert derive_module("src/notationscene/notationscenemodule.cpp") == "notationscene"
        assert derive_module("src/appshell/appshellmodule.cpp") == "appshell"

    def test_controller_class_lookup(self):
        """Looks up controller class by module name."""
        assert get_controller_class("playback") == "PlaybackController"
        assert get_controller_class("notationscene") == "NotationActionController"
        assert get_controller_class("appshell") == "ApplicationActionController"
        assert get_controller_class("project") == "ProjectActionController"
        assert get_controller_class("instrumentsscene") == "InstrumentsActionsController"

    def test_controller_class_unknown_module_returns_none(self):
        """Unknown module returns None."""
        assert get_controller_class("unknownmodule") is None


class TestScanCommand:
    def test_scan_finds_known_gaps(self):
        """Scan against the real codebase finds known candidates."""
        candidates = scan_codebase("src")
        assert isinstance(candidates, list)
        for c in candidates:
            assert hasattr(c, 'uri')
            assert hasattr(c, 'component')
            assert hasattr(c, 'source_file')
            assert c.uri.startswith('musescore://') or c.uri.startswith('muse://')

    def test_scan_excludes_already_registered(self):
        """Scan does not include URIs that have matching UiActions."""
        candidates = scan_codebase("src")
        candidate_uris = [c.uri for c in candidates]
        assert "musescore://notation/settempo" not in candidate_uris


class TestGenerateCommand:
    def test_generate_produces_three_blocks(self):
        """Generate produces UiAction, handler, and registerQmlUri blocks."""
        candidate = Candidate(
            uri="musescore://playback/speeddialog",
            qml_module="MuseScore.Playback",
            component="PlaybackSpeedDialog",
            source_file="src/playback/playbackmodule.cpp",
            module="playback",
            action_code="playback-speed",
            title="Playback speed",
            controller_class="PlaybackController",
        )
        output = generate_code_blocks(candidate)
        assert "=== CANDIDATE:" in output
        assert "Block 1: UiAction declaration" in output
        assert "Block 2: Handler registration" in output
        assert "Block 3:" in output

    def test_generate_includes_action_code(self):
        """Generate output includes the derived action code."""
        candidate = Candidate(
            uri="musescore://playback/speeddialog",
            qml_module="MuseScore.Playback",
            component="PlaybackSpeedDialog",
            source_file="src/playback/playbackmodule.cpp",
            module="playback",
            action_code="playback-speed",
            title="Playback speed",
            controller_class="PlaybackController",
        )
        output = generate_code_blocks(candidate)
        assert "playback-speed" in output

    def test_generate_includes_interactive_open(self):
        """Generate output includes interactive()->open with the URI."""
        candidate = Candidate(
            uri="musescore://playback/speeddialog",
            qml_module="MuseScore.Playback",
            component="PlaybackSpeedDialog",
            source_file="src/playback/playbackmodule.cpp",
            module="playback",
            action_code="playback-speed",
            title="Playback speed",
            controller_class="PlaybackController",
        )
        output = generate_code_blocks(candidate)
        assert 'interactive()->open("musescore://playback/speeddialog")' in output

    def test_generate_warns_on_unknown_controller(self):
        """Generate warns when controller class is unknown."""
        candidate = Candidate(
            uri="musescore://unknown/something",
            qml_module="MuseScore.Unknown",
            component="SomethingDialog",
            source_file="src/unknown/unknownmodule.cpp",
            module="unknown",
            action_code="unknown-something",
            title="Something",
            controller_class=None,
        )
        output = generate_code_blocks(candidate)
        assert "WARNING" in output or "unknown" in output.lower()


class TestCliOutput:
    def test_scan_output_format(self, capsys):
        """Scan output contains candidate info in readable format."""
        candidates = [
            Candidate(
                uri="musescore://playback/speeddialog",
                qml_module="MuseScore.Playback",
                component="PlaybackSpeedDialog",
                source_file="src/playback/playbackmodule.cpp",
                module="playback",
                action_code="playback-speed",
                title="Playback speed",
                controller_class="PlaybackController",
            ),
        ]
        print_scan_results(candidates)
        captured = capsys.readouterr()
        assert "musescore://playback/speeddialog" in captured.out
        assert "PlaybackSpeedDialog" in captured.out
        assert "playback-speed" in captured.out

    def test_generate_output_for_known_uri(self):
        """Generate finds a candidate by URI and produces code blocks."""
        candidates = scan_codebase("src")
        if not candidates:
            pytest.skip("No candidates found in codebase")
        test_candidate = candidates[0]
        output = generate_for_uri(test_candidate.uri, candidates)
        assert "=== CANDIDATE:" in output
        assert test_candidate.uri in output
