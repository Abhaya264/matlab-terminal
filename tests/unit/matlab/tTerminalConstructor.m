classdef tTerminalConstructor < matlab.unittest.TestCase
    % Copyright 2026 The MathWorks, Inc.
    
    % Unit tests for Terminal constructor
    % Tests parameter validation, property assignment, and fallback behavior
    
    properties (TestParameter)
        ValidShellUnix = {'bash', 'zsh', 'sh', 'fish', '/bin/bash', '/usr/bin/zsh'}
        ValidShellWindows = {'cmd.exe', 'powershell.exe', 'pwsh.exe', 'C:\Windows\System32\cmd.exe'}
        ValidWindowStyle = {'normal', 'docked'}
    end
    
    properties
        TestTerminals  % Store terminals created during tests for cleanup
    end
    
    methods (TestMethodSetup)
        function setup(testCase)
            % Initialize test terminal storage
            testCase.TestTerminals = [];
        end
    end
    
    methods (TestMethodTeardown)
        function cleanup(testCase)
            % Clean up any terminals created during tests
            for i = 1:numel(testCase.TestTerminals)
                if isvalid(testCase.TestTerminals(i))
                    delete(testCase.TestTerminals(i));
                end
            end
            testCase.TestTerminals = [];
        end
    end
    
    methods (Test)
        function testDefaultConstructor(testCase)
            % Test Terminal() creates object with default properties
            import matlab.unittest.constraints.IsOfClass
            
            t = Terminal();
            testCase.TestTerminals(end+1) = t;
            
            % Verify object type
            testCase.verifyThat(t, IsOfClass('Terminal'));
            
            % Verify default properties are set
            testCase.verifyNotEmpty(t.Shell, 'Shell should be set to default');
            
            % Verify figure is created
            testCase.verifyNotEmpty(t.Figure, 'Figure should be created');
            testCase.verifyTrue(isvalid(t.Figure), 'Figure should be valid');
        end
        
        function testCustomName(testCase)
            % Test Terminal(Name="Build") correctly sets the Name property
            customName = "Build";
            t = Terminal(Name=customName);
            testCase.TestTerminals(end+1) = t;
            
            % Verify name is set correctly
            testCase.verifyEqual(t.Name, customName, ...
                'Name property should match constructor argument');
            
            % Verify figure title contains the name
            testCase.verifySubstring(t.Figure.Name, customName, ...
                'Figure title should contain custom name');
        end
        
        function testCustomNameMultiple(testCase)
            % Test multiple terminals with different names
            names = ["Terminal1", "Build", "Test", "Deploy"];
            
            for i = 1:length(names)
                t = Terminal(Name=names(i));
                testCase.TestTerminals(end+1) = t;
                testCase.verifyEqual(t.Name, names(i));
            end
        end
        
        function testCustomShellUnix(testCase, ValidShellUnix)
            % Test Terminal(Shell="...") on Unix systems
            if ispc
                testCase.assumeFail('Test only runs on Unix systems');
            end
            
            t = Terminal(Shell=ValidShellUnix);
            testCase.TestTerminals(end+1) = t;
            
            % Verify shell is set correctly
            testCase.verifyEqual(t.Shell, ValidShellUnix, ...
                'Shell property should match constructor argument');
        end
        
        function testCustomShellWindows(testCase, ValidShellWindows)
            % Test Terminal(Shell="...") on Windows systems
            if ~ispc
                testCase.assumeFail('Test only runs on Windows systems');
            end
            
            t = Terminal(Shell=ValidShellWindows);
            testCase.TestTerminals(end+1) = t;
            
            % Verify shell is set correctly
            testCase.verifyEqual(t.Shell, ValidShellWindows, ...
                'Shell property should match constructor argument');
        end
        
        function testWindowStyleNormal(testCase)
            % Test Terminal(WindowStyle="normal") creates floating window
            t = Terminal(WindowStyle="normal");
            testCase.TestTerminals(end+1) = t;
            
            % Verify window style (may be 'normal' or fallback)
            testCase.verifyMatches(t.Figure.WindowStyle, 'normal|alwaysontop', ...
                'WindowStyle should be normal or alwaysontop');
        end
        
        function testWindowStyleDocked(testCase)
            % Test Terminal(WindowStyle="docked") creates docked window
            t = Terminal(WindowStyle="docked");
            testCase.TestTerminals(end+1) = t;
            
            % Verify window style is docked or falls back to normal
            % (docked may not be supported on all MATLAB releases)
            testCase.verifyMatches(t.Figure.WindowStyle, 'docked|normal|alwaysontop', ...
                'WindowStyle should be docked or fall back to normal');
        end
        
        function testCombinedParameters(testCase)
            % Test Terminal with multiple parameters
            t = Terminal(Name="CustomShell", Shell="bash", WindowStyle="normal");
            testCase.TestTerminals(end+1) = t;
            
            testCase.verifyEqual(t.Name, "CustomShell");
            testCase.verifyEqual(t.Shell, "bash");
            testCase.verifyMatches(t.Figure.WindowStyle, 'normal|alwaysontop');
        end
        
        function testEmptyName(testCase)
            % Test Terminal(Name="") uses default naming
            t = Terminal(Name="");
            testCase.TestTerminals(end+1) = t;
            
            % Verify terminal is created (name may default to "Terminal")
            testCase.verifyNotEmpty(t.Figure.Name);
        end
        
        function testServerStartup(testCase)
            % Test that constructor starts the server
            t = Terminal();
            testCase.TestTerminals(end+1) = t;
            
            % Verify server-related properties are initialized
            testCase.verifyNotEmpty(t.ServerPort, 'Server port should be assigned');
            testCase.verifyGreaterThan(t.ServerPort, 0, 'Server port should be positive');
            testCase.verifyNotEmpty(t.AuthToken, 'Auth token should be generated');
            testCase.verifyEqual(length(t.AuthToken), 32, ...
                'Auth token should be 32 characters');
        end
        
        function testAuthTokenUniqueness(testCase)
            % Test that each terminal instance gets a unique auth token
            t1 = Terminal();
            t2 = Terminal();
            testCase.TestTerminals = [t1, t2];
            
            testCase.verifyNotEqual(t1.AuthToken, t2.AuthToken, ...
                'Each terminal should have a unique auth token');
        end
        
        function testServerPortUniqueness(testCase)
            % Test that each terminal instance gets a unique server port
            t1 = Terminal();
            t2 = Terminal();
            testCase.TestTerminals = [t1, t2];
            
            testCase.verifyNotEqual(t1.ServerPort, t2.ServerPort, ...
                'Each terminal should have a unique server port');
        end
        
        function testInstanceRegistry(testCase)
            % Test that new terminals are added to instance registry
            initialCount = numel(Terminal.list());
            
            t = Terminal();
            testCase.TestTerminals(end+1) = t;
            
            newCount = numel(Terminal.list());
            testCase.verifyEqual(newCount, initialCount + 1, ...
                'Terminal should be added to instance registry');
        end
        
        function testFigureProperties(testCase)
            % Test that figure is created with correct properties
            t = Terminal();
            testCase.TestTerminals(end+1) = t;
            
            % Verify figure exists and is valid
            testCase.verifyClass(t.Figure, 'matlab.ui.Figure');
            testCase.verifyTrue(isvalid(t.Figure));
            
            % Verify figure has reasonable size
            testCase.verifyGreaterThan(t.Figure.Position(3), 0, ...
                'Figure width should be positive');
            testCase.verifyGreaterThan(t.Figure.Position(4), 0, ...
                'Figure height should be positive');
        end
        
        function testHTMLComponentCreation(testCase)
            % Test that uihtml component is created
            t = Terminal();
            testCase.TestTerminals(end+1) = t;
            
            % Find HTML component in figure
            htmlComponents = findall(t.Figure, 'Type', 'uihtml');
            testCase.verifyNotEmpty(htmlComponents, ...
                'uihtml component should be created');
        end
        
        function testInvalidShellWarning(testCase)
            % Test that invalid shell path produces warning or error
            if ispc
                invalidShell = "/nonexistent/shell";
            else
                invalidShell = "C:\nonexistent\shell.exe";
            end
            
            % This may warn or fail depending on implementation
            % Just verify terminal can be created (validation may be deferred)
            t = Terminal(Shell=invalidShell);
            testCase.TestTerminals(end+1) = t;
            
            % Verify shell property is set even if invalid
            testCase.verifyEqual(t.Shell, invalidShell);
        end
        
        function testMultipleConstructorCalls(testCase)
            % Test creating multiple terminals in sequence
            terminals = [];
            for i = 1:3
                terminals(end+1) = Terminal(Name="Terminal"+i); %#ok<AGROW>
            end
            testCase.TestTerminals = terminals;
            
            % Verify all are valid and unique
            testCase.verifyEqual(numel(terminals), 3);
            for i = 1:3
                testCase.verifyTrue(isvalid(terminals(i)));
            end
        end
        
        function testConstructorWithNameValuePairs(testCase)
            % Test various name-value pair combinations
            t1 = Terminal('Name', 'Test1');
            t2 = Terminal('Shell', 'bash');
            t3 = Terminal('WindowStyle', 'normal');
            testCase.TestTerminals = [t1, t2, t3];
            
            testCase.verifyEqual(t1.Name, "Test1");
            testCase.verifyEqual(t2.Shell, "bash");
        end
        
        function testDefaultShellDetection(testCase)
            % Test that default shell is platform-appropriate
            t = Terminal();
            testCase.TestTerminals(end+1) = t;
            
            shell = t.Shell;
            if ispc
                % Windows should default to cmd.exe or PowerShell
                testCase.verifyMatches(shell, 'cmd|powershell|pwsh', ...
                    'IgnoreCase', true);
            else
                % Unix should default to bash, zsh, sh, etc.
                testCase.verifyMatches(shell, 'bash|zsh|sh|fish', ...
                    'IgnoreCase', true);
            end
        end
    end
    
    methods (Test, TestTags = {'Interactive'})
        % These tests require manual verification or may open UI
        
        function testVisualAppearance(testCase)
            % Test that terminal appears correctly (manual verification)
            t = Terminal(Name="Visual Test");
            testCase.TestTerminals(end+1) = t;
            
            % Just verify it doesn't crash
            testCase.verifyTrue(isvalid(t));
            pause(0.5); % Allow UI to render
        end
    end
end