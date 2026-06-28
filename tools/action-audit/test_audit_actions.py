import pytest
from audit_actions import (
    CppParser,
    extract_register_qml_uri_calls,
    extract_ui_action_codes,
    extract_open_calls,
    extract_registrations,
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


class TestOpenCallExtraction:
    def test_extracts_string_literal_uri(self):
        """Extracts URI from interactive()->open("uri") with a string literal."""
        code = b'''
        void Controller::openDialog() {
            interactive()->open("musescore://playback/speeddialog");
        }
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_open_calls(tree, code, "src/playback/internal/controller.cpp")
        assert len(results) == 1
        assert results[0].uri == "musescore://playback/speeddialog"
        assert results[0].method_name == "openDialog"

    def test_extracts_uri_call(self):
        """Extracts URI from interactive()->open(Uri("uri"))."""
        code = b'''
        void Controller::openDialog() {
            interactive()->open(Uri("musescore://project/export"));
        }
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_open_calls(tree, code, "src/project/internal/controller.cpp")
        assert len(results) == 1
        assert results[0].uri == "musescore://project/export"

    def test_resolves_uri_variable(self):
        """Resolves a Uri variable: static const Uri VAR("uri"); open(VAR)."""
        code = b'''
        void Controller::exportScore() {
            static const Uri EXPORT_URI("musescore://project/export");
            if (!interactive()->isOpened(EXPORT_URI).val) {
                interactive()->open(EXPORT_URI);
            }
        }
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_open_calls(tree, code, "src/project/internal/controller.cpp")
        assert len(results) == 1
        assert results[0].uri == "musescore://project/export"
        assert results[0].method_name == "exportScore"

    def test_finds_enclosing_method_name(self):
        """Correctly identifies the enclosing method name."""
        code = b'''
        void NotationActionController::openEditGridSizeDialog() {
            interactive()->open("musescore://notation/editgridsize");
        }
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_open_calls(tree, code, "src/notationscene/internal/controller.cpp")
        assert len(results) == 1
        assert results[0].method_name == "openEditGridSizeDialog"

    def test_ignores_non_interactive_open(self):
        """Does not extract calls from non-interactive()->open() calls."""
        code = b'''
        void Foo::bar() {
            fileDialog->open("some/file/path");
        }
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_open_calls(tree, code, "src/foo/internal/controller.cpp")
        assert len(results) == 0


class TestRegistrationExtraction:
    def test_extracts_lambda_handler(self):
        """Extracts action code and method name from reg() with a lambda."""
        code = b'''
        void Controller::init() {
            dispatcher()->reg(this, "play", [this]() { togglePlay(); });
        }
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_registrations(tree, code, "src/playback/internal/controller.cpp")
        assert len(results) == 1
        assert results[0].action_code == "play"
        assert results[0].method_name == "togglePlay"

    def test_extracts_function_pointer_handler(self):
        """Extracts action code and method name from reg() with &Controller::method."""
        code = b'''
        void Controller::init() {
            dispatcher()->reg(this, "about-musescore", this, &ApplicationActionController::openAboutDialog);
        }
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_registrations(tree, code, "src/appshell/internal/controller.cpp")
        assert len(results) == 1
        assert results[0].action_code == "about-musescore"
        assert results[0].method_name == "openAboutDialog"

    def test_extracts_register_action(self):
        """Extracts from registerAction("code", &Controller::method)."""
        code = b'''
        void Controller::init() {
            registerAction("config-raster", &Controller::openEditGridSizeDialog);
        }
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_registrations(tree, code, "src/notationscene/internal/controller.cpp")
        assert len(results) == 1
        assert results[0].action_code == "config-raster"
        assert results[0].method_name == "openEditGridSizeDialog"

    def test_extracts_multiple_registrations(self):
        """Extracts multiple registrations from one file."""
        code = b'''
        void Controller::init() {
            dispatcher()->reg(this, "play", [this]() { togglePlay(); });
            dispatcher()->reg(this, "stop", this, &Controller::stop);
            registerAction("rewind", &Controller::rewind);
        }
        '''
        parser = CppParser()
        tree = parser.parse(code)
        results = extract_registrations(tree, code, "src/playback/internal/controller.cpp")
        assert len(results) == 3
        codes = {r.action_code for r in results}
        assert codes == {"play", "stop", "rewind"}


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
        assert get_controller_class("project") == "ProjectActionsController"
        assert get_controller_class("instrumentsscene") == "InstrumentsActionsController"

    def test_controller_class_unknown_module_returns_none(self):
        """Unknown module returns None."""
        assert get_controller_class("unknownmodule") is None


class TestScanCommand:
    def test_scan_returns_candidates(self):
        """Scan against the real codebase returns a list of candidates."""
        candidates = scan_codebase("src")
        assert isinstance(candidates, list)
        for c in candidates:
            assert hasattr(c, 'uri')
            assert hasattr(c, 'component')
            assert hasattr(c, 'source_file')
            assert hasattr(c, 'reason')
            assert c.uri.startswith('musescore://') or c.uri.startswith('muse://')

    def test_scan_excludes_fully_wired_chains(self):
        """Scan does NOT flag URIs with a complete handler chain.

        These URIs have: interactive()->open("uri") in a method →
        that method is registered via reg("code", &Controller::method) →
        "code" has a UiAction declaration. They should NOT appear as gaps.
        """
        candidates = scan_codebase("src")
        candidate_uris = {c.uri for c in candidates}

        # about/musescore: reg("about-musescore", &ApplicationActionController::openAboutDialog)
        # → openAboutDialog opens "musescore://about/musescore" → UiAction("about-musescore")
        assert "musescore://about/musescore" not in candidate_uris, \
            "about/musescore should NOT be a gap — it has a complete chain"

        # about/musicxml: reg("about-musicxml", &ApplicationActionController::openAboutMusicXMLDialog)
        # → opens "musescore://about/musicxml" → UiAction("about-musicxml")
        assert "musescore://about/musicxml" not in candidate_uris, \
            "about/musicxml should NOT be a gap — it has a complete chain"

        # project/export: reg("file-export", &ProjectActionsController::exportScore)
        # → exportScore opens "musescore://project/export" (via Uri variable) → UiAction("file-export")
        # This tests Uri variable resolution: open(EXPORT_URI) where EXPORT_URI is
        # declared as static const Uri EXPORT_URI("musescore://project/export")
        assert "musescore://project/export" not in candidate_uris, \
            "project/export should NOT be a gap — file-export action opens it"

    def test_scan_includes_true_gaps(self):
        """Scan DOES flag URIs with no complete handler chain."""
        candidates = scan_codebase("src")
        candidate_uris = {c.uri for c in candidates}
        candidate_by_uri = {c.uri: c for c in candidates}

        # Diagnostics dialogs have no handler at all — true gaps
        diagnostics_found = [uri for uri in candidate_uris if "diagnostics" in uri]
        assert len(diagnostics_found) > 0, \
            "Diagnostics URIs should appear as gaps (no handler chain)"

        # notation/editgridsize: registerAction("config-raster", &Controller::openEditGridSizeDialog)
        # → opens "musescore://notation/editgridsize" → but config-raster has NO UiAction
        # This is a TRUE gap: the handler exists and is registered, but the action code
        # has no UiAction declaration, so the dialog can't be reached from the palette.
        assert "musescore://notation/editgridsize" in candidate_uris, \
            "notation/editgridsize SHOULD be a gap — config-raster has no UiAction"
        editgrid = candidate_by_uri["musescore://notation/editgridsize"]
        assert editgrid.reason == "no-uiaction", \
            f"editgridsize reason should be 'no-uiaction', got '{editgrid.reason}'"


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
            reason="no-handler",
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
            reason="no-handler",
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
            reason="no-handler",
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
            reason="no-handler",
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
                reason="no-handler",
            ),
        ]
        print_scan_results(candidates)
        captured = capsys.readouterr()
        assert "musescore://playback/speeddialog" in captured.out
        assert "PlaybackSpeedDialog" in captured.out
        assert "playback-speed" in captured.out
        assert "no-handler" in captured.out

    def test_generate_output_for_known_uri(self):
        """Generate finds a candidate by URI and produces code blocks."""
        candidates = scan_codebase("src")
        if not candidates:
            pytest.skip("No candidates found in codebase")
        test_candidate = candidates[0]
        output = generate_for_uri(test_candidate.uri, candidates)
        assert "=== CANDIDATE:" in output
        assert test_candidate.uri in output
