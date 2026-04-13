% Copyright 2026 The MathWorks, Inc.

classdef TestTerminalIntegration < matlab.unittest.TestCase
    %TESTTERMINALINTEGRATION Integration tests for Terminal that require a
    %   display (uifigure) and the bundled server binary.

    properties (Access = private)
        Terminals = Terminal.empty  % track instances for cleanup
    end

    methods (TestClassSetup)
        function checkPrerequisites(testCase)
            % Skip the entire class if we cannot create a Terminal.
            % This covers: no display, no server binary, no uifigure, etc.
            try
                t = Terminal(WindowStyle="normal");
                pause(1);  % let server start
                delete(t);
            catch me
                testCase.assumeFail(sprintf( ...
                    'Cannot create Terminal (%s) — skipping integration tests.', ...
                    me.message));
            end
        end
    end

    methods (TestMethodTeardown)
        function closeTerminals(testCase) %#ok<MANU>
            % Clean up any terminals opened during the test.
            Terminal.closeAll();
            pause(0.5);
        end
    end

    %% --- Constructor tests ---

    methods (Test)
        function testDefaultConstructor(testCase)
            t = Terminal();
            testCase.addTeardown(@() safeDelete(t));
            testCase.Terminals(end+1) = t;
            testCase.verifyClass(t, 'Terminal');
        end

        function testConstructorWithName(testCase)
            t = Terminal(Name="Build");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'Terminal');
        end

        function testConstructorNormal(testCase)
            t = Terminal(WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'Terminal');
        end

        function testConstructorDocked(testCase)
            t = Terminal(WindowStyle="docked");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'Terminal');
        end

        function testConstructorWithTheme(testCase)
            t = Terminal(Theme="dracula");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'Terminal');
            testCase.verifyEqual(t.Theme, "dracula");
        end

        function testConstructorWithShell(testCase)
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
            fig = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(fig));
            t = Terminal(fig);
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'Terminal');
        end

        function testConstructorWithPanel(testCase)
            fig = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(fig));
            panel = uipanel(fig, 'Position', [10 10 400 300]);
            t = Terminal(panel);
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyClass(t, 'Terminal');
        end

        %% --- Lifecycle tests ---

        function testDeleteCleansUp(testCase)
            t = Terminal(WindowStyle="normal");
            testCase.verifyTrue(isvalid(t));
            delete(t);
            testCase.verifyFalse(isvalid(t));
        end

        function testMultipleTerminals(testCase)
            t1 = Terminal(Name="Term1", WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t1));
            t2 = Terminal(Name="Term2", WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t2));

            terminals = Terminal.list();
            testCase.verifyGreaterThanOrEqual(numel(terminals), 2);
        end

        function testCloseAll(testCase)
            Terminal(Name="CloseMe1", WindowStyle="normal");
            Terminal(Name="CloseMe2", WindowStyle="normal");
            testCase.verifyGreaterThanOrEqual(numel(Terminal.list()), 2);

            Terminal.closeAll();
            pause(0.5);
            testCase.verifyEmpty(Terminal.list());
        end

        function testListReflectsCreationAndDeletion(testCase)
            before = numel(Terminal.list());
            t = Terminal(WindowStyle="normal");
            testCase.verifyEqual(numel(Terminal.list()), before + 1);
            delete(t);
            testCase.verifyEqual(numel(Terminal.list()), before);
        end

        %% --- Theme tests ---

        function testLiveThemeChange(testCase)
            t = Terminal(Theme="dark", WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(t.Theme, "dark");

            t.Theme = "monokai";
            testCase.verifyEqual(t.Theme, "monokai");
        end

        function testLiveThemeChangeAllPresets(testCase)
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
            t = Terminal(WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));

            custom = struct('background', '#ff0000', 'foreground', '#00ff00');
            t.Theme = custom;
            testCase.verifyTrue(isstruct(t.Theme));
        end

        function testConstructorWithDefaultTheme(testCase)
            % Verify that the default theme preference is used.
            original = Terminal.getDefaultTheme();
            testCase.addTeardown(@() Terminal.setDefaultTheme(original));

            Terminal.setDefaultTheme("nord");
            t = Terminal(WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(string(t.Theme), "nord");
        end

        function testConstructorThemeOverridesDefault(testCase)
            original = Terminal.getDefaultTheme();
            testCase.addTeardown(@() Terminal.setDefaultTheme(original));

            Terminal.setDefaultTheme("nord");
            t = Terminal(Theme="dracula", WindowStyle="normal");
            testCase.addTeardown(@() safeDelete(t));
            testCase.verifyEqual(t.Theme, "dracula");
        end
    end
end

function safeDelete(t)
    if isvalid(t)
        delete(t);
    end
end
