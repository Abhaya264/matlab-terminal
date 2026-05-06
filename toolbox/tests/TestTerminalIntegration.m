% Copyright 2026 The MathWorks, Inc.

classdef TestTerminalIntegration < matlab.unittest.TestCase
    %TESTTERMINALINTEGRATION Integration tests for Terminal.
    %   Tests that need a display (uifigure) skip gracefully in headless
    %   environments. Tests that only validate error paths or class
    %   properties run everywhere.

    properties (Access = private)
        Terminals = Terminal.empty  % track instances for cleanup
    end

    methods (TestMethodTeardown)
        function closeTerminals(testCase) %#ok<MANU>
            % Clean up any terminals opened during the test.
            Terminal.closeAll();
            pause(0.5);
        end
    end

    methods (Access = private)
        function requireDisplay(testCase)
            %REQUIREDISPLAY Skip the current test if no display is available.
            try
                fig = uifigure('Visible', 'off');
                delete(fig);
                fprintf('[TestDebug] uifigure(Visible=off) succeeded\n');
            catch me
                fprintf('[TestDebug] uifigure(Visible=off) FAILED: %s\n', me.message);
                testCase.assumeFail(sprintf( ...
                    'No display available (%s) — skipping.', me.message));
            end
        end

        function requireServer(testCase)
            %REQUIRESERVER Skip the current test if the server binary is not found.
            testCase.requireDisplay();
            try
                t = Terminal(WindowStyle="normal");
                pause(1);
                delete(t);
                fprintf('[TestDebug] Terminal creation succeeded\n');
            catch me
                fprintf('[TestDebug] Terminal creation FAILED: %s (%s)\n', me.message, me.identifier);
                testCase.assumeFail(sprintf( ...
                    'Cannot create Terminal (%s) — skipping.', me.message));
            end
        end
    end

    %% --- Constructor tests ---

    methods (Test)
        function testDefaultConstructor(testCase)
            testCase.requireServer();
            t = Terminal();
            testCase.addTeardown(@() safeDelete(t));
            testCase.Terminals(end+1) = t;
            testCase.verifyClass(t, 'Terminal');
        end

        function testConstructorWithName(testCase)
            testCase.requireServer();
            t = Terminal(Name="Build");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'Terminal');
        end

        function testConstructorNormal(testCase)
            testCase.requireServer();
            t = Terminal(WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'Terminal');
        end

        function testConstructorDocked(testCase)
            testCase.requireServer();
            t = Terminal(WindowStyle="docked");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'Terminal');
        end

        function testConstructorWithTheme(testCase)
            testCase.requireServer();
            t = Terminal(Theme="dracula");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'Terminal');
            testCase.verifyEqual(t.Theme, "dracula");
        end

        function testConstructorWithShell(testCase)
            testCase.requireServer();
            if ispc
                shell = "cmd.exe";
            else
                shell = "/bin/bash";
            end
            t = Terminal(Shell=shell);
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'Terminal');
            testCase.verifyEqual(t.Shell, shell);
        end

        function testConstructorAllOptions(testCase)
            testCase.requireServer();
            if ispc
                shell = "cmd.exe";
            else
                shell = "/bin/bash";
            end
            t = Terminal(Name="Full", WindowStyle="normal", ...
                Shell=shell, Theme="monokai");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'Terminal');
            testCase.verifyEqual(t.Theme, "monokai");
            testCase.verifyEqual(t.Shell, shell);
        end

        function testConstructorInvalidShell(testCase)
            testCase.verifyError(...
                @() Terminal(Shell="/no/such/shell_xyz"), ...
                'Terminal:ShellNotFound');
        end

        function testConstructorInvalidTheme(testCase)
            testCase.verifyError(...
                @() Terminal(Theme="nonexistent-theme-xyz"), ...
                'Terminal:InvalidTheme');
        end

        function testConstructorInvalidWindowStyle(testCase)
            testCase.verifyError(...
                @() Terminal(WindowStyle="invalid"), ...
                'MATLAB:validators:mustBeMember');
        end

        function testConstructorWithParent(testCase)
            testCase.requireServer();
            fig = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(fig));
            t = Terminal(fig);
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'Terminal');
        end

        function testConstructorWithPanel(testCase)
            testCase.requireServer();
            fig = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(fig));
            panel = uipanel(fig, 'Position', [10 10 400 300]);
            t = Terminal(panel);
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'Terminal');
        end

        %% --- Lifecycle tests ---

        function testDeleteCleansUp(testCase)
            testCase.requireServer();
            t = Terminal(WindowStyle="normal");
            testCase.verifyTrue(isvalid(t));
            delete(t);
            testCase.verifyFalse(isvalid(t));
        end

        function testMultipleTerminals(testCase)
            testCase.requireServer();
            t1 = Terminal(Name="Term1", WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t1));
            t2 = Terminal(Name="Term2", WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t2));

            terminals = Terminal.list();
            testCase.verifyGreaterThanOrEqual(numel(terminals), 2);
        end

        function testCloseAll(testCase)
            testCase.requireServer();
            Terminal(Name="CloseMe1", WindowStyle="normal");
            Terminal(Name="CloseMe2", WindowStyle="normal");
            testCase.verifyGreaterThanOrEqual(numel(Terminal.list()), 2);

            Terminal.closeAll();
            pause(0.5);
            testCase.verifyEmpty(Terminal.list());
        end

        function testListReflectsCreationAndDeletion(testCase)
            testCase.requireServer();
            before = numel(Terminal.list());
            t = Terminal(WindowStyle="normal");
            testCase.verifyEqual(numel(Terminal.list()), before + 1);
            delete(t);
            testCase.verifyEqual(numel(Terminal.list()), before);
        end

        %% --- Theme tests ---

        function testLiveThemeChange(testCase)
            testCase.requireServer();
            t = Terminal(Theme="dark", WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(t.Theme, "dark");

            t.Theme = "monokai";
            testCase.verifyEqual(t.Theme, "monokai");
        end

        function testLiveThemeChangeAllPresets(testCase)
            testCase.requireServer();
            t = Terminal(WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));

            names = Terminal.themes();
            for i = 1:numel(names)
                t.Theme = names(i);
                testCase.verifyEqual(string(t.Theme), names(i), ...
                    sprintf('Failed to set theme to %s', names(i)));
            end
        end

        function testLiveThemeChangeCustomStruct(testCase)
            testCase.requireServer();
            t = Terminal(WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));

            custom = struct('background', '#ff0000', 'foreground', '#00ff00');
            t.Theme = custom;
            testCase.verifyTrue(isstruct(t.Theme));
        end

        function testConstructorWithDefaultTheme(testCase)
            testCase.requireServer();
            original = Terminal.getDefaultTheme();
            testCase.addTeardown(@() Terminal.setDefaultTheme(original));

            Terminal.setDefaultTheme("nord");
            t = Terminal(WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(string(t.Theme), "nord");
        end

        function testConstructorThemeOverridesDefault(testCase)
            testCase.requireServer();
            original = Terminal.getDefaultTheme();
            testCase.addTeardown(@() Terminal.setDefaultTheme(original));

            Terminal.setDefaultTheme("nord");
            t = Terminal(Theme="dracula", WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(t.Theme, "dracula");
        end

        %% --- UI Layout and State Tests ---

        function testTerminalVisibilityToggle(testCase)
            testCase.requireServer();
            fig = uifigure();
            testCase.addTeardown(@() delete(fig));

            t = Terminal(fig);
            testCase.addTeardown(@() safeDelete(t));

            pause(0.5);

            fig.Visible = 'off';
            pause(0.1);
            testCase.verifyEqual(fig.Visible, char('off'));

            fig.Visible = 'on';
            pause(0.1);
            testCase.verifyEqual(fig.Visible, char('on'));

            testCase.verifyTrue(isvalid(t), 'Terminal should remain valid after visibility toggle');
        end
    end
end

function safeDelete(t)
    if isvalid(t)
        delete(t);
    end
end
