function bimanual_R_mode(goalSuccessesInput)
global targetCenters targetSequence circleDiameter circleDiameter2 radii;
global centerHoldDuration centerEnterTime hoverEnterTime targetHoldDuration centerActivated centerHoldStartTime;
global firstMove firstMovementThreshold resetPosition targetReachedOnce;
global targetActivated currentTarget remoteCenterIdx lastCenterSent;
global cyclesCompleted maxCycles mousePath timerObj rxbuf awaitingAck4 lastSend4Time ack4Tries;
global lastMoveTime;
global mouseDot ax fig screenSize barrierRemoteReady barrierRemoteDone barrierLocalReady barrierLocalDone;
global tcpObj isServer ttlStartDiff ttlEndDiff;
global daqSession centerexittime localCenterDone remoteCenterDone trialIndex;
global localSuccess remoteSuccess  ttlFirstMove ttlEnd remoteTtlFirst remoteTtlEnd;
global goalSuccesses successCount;

TOUCH_ACTIVE_LEVEL = 1;
TOUCH_FRAMES       = 10;
CENTER_SYNC_GO_LEAD = 0.008;
TARGET_SYNC_GO_LEAD = 0.008;
SYNC_PREPARE_RETRY_INTERVAL = 0.008;
SYNC_PREPARE_MAX_TRIES      = 300;
SYNC_GO_RETRY_INTERVAL      = 0.008;
SYNC_GO_MAX_TRIES           = 200;
CLOCK_SYNC_SAMPLE_COUNT     = 8;
CLOCK_SYNC_REPLY_TIMEOUT    = 1.0;
CLOCK_SYNC_SET_TIMEOUT      = 1.0;
CENTER_ACK_RETRY_INTERVAL  = 0.008;
CENTER_ACK_MAX_TRIES       = 300;
COMMIT_RETRY_INTERVAL      = 0.008;
COMMIT_MAX_TRIES           = 10;
DEFAULT_TARGET_SEQUENCE    = [1, 3, 5, 7];
DEFAULT_BLACK_SCREEN_DURATIONS = [4, 4.5, 5];
DEFAULT_TTL_DIFF_THRESHOLD = 0.3;
DEFAULT_TARGET_DIAMETER    = 0.12;
DEFAULT_CENTER_DIAMETER    = 0.12;
DEFAULT_RADIUS             = 0.24;
DEFAULT_CENTER_HOLD        = 0.8;
DEFAULT_TARGET_HOLD        = 0.8;
DEFAULT_FIRST_MOVE_THRESHOLD = 0.0184;
STATUS_SUCCESS        = 1;
STATUS_TTL_MISMATCH   = 7;
STATUS_R_CENTER_EXIT  = 12;
STATUS_R_CENTER_REL   = 13;
STATUS_R_TARGET_EXIT  = 14;
STATUS_R_TARGET_REL   = 15;
STATUS_R_TIMEOUT      = 16;
OP_TARGET_DONE = 2;
OP_FAIL        = 3;
OP_CENTER_DONE = 4;
OP_CENTER_ACK  = 5;
OP_COMMIT      = 7;
OP_TARGET_DONE_ACK = 9;
OP_READY       = 10;
OP_DONE        = 11;
OP_COMMIT_ACK  = 12;
OP_PREPARE_ONSET = 13;
OP_READY_FOR_GO  = 14;
OP_GO_CUE        = 15;
OP_GO_ACK        = 16;
OP_CLOCK_SYNC_REQ   = 17;
OP_CLOCK_SYNC_REPLY = 18;
OP_CLOCK_SYNC_SET   = 19;
OP_STOP        = 20;
OP_SESSION_CONFIG = 21;
OP_SESSION_CONFIG_ACK = 22;
OP_CLOCK_SYNC_ACK = 23;
OP_CENTER_HOLD_START = 24;
OP_CENTER_HOLD_START_ACK = 25;
EVENT_CENTER_ON = 1;
EVENT_TARGET_ON = 2;
CENTER_EXIT_SOURCE_NONE = 0;
CENTER_EXIT_SOURCE_LOGIC = 1;
CENTER_EXIT_SOURCE_TARGET_ON_FILL = 2;
MODE_INPHASE   = 1;
MODE_ANTIPHASE = 2;
MODE_QUARTER   = 3;
ERROR_REQUEUE_TO_END = 1;
ERROR_IMMEDIATE_REDO = 2;
ERROR_RESHUFFLE = 3;
touchStable = 0;
touchHiCnt  = 0;
touchLoCnt  = 0;
firstMoveStartPos = [NaN, NaN];
syncClock = tic;
clockOffsetToShared = 0;
trialStartEpochShared = NaN;
clockSyncReplySeq = -1;
clockSyncReplyMasterSend = NaN;
clockSyncReplyRemoteMono = NaN;
clockSyncSetSeq = -1;
clockSyncSetAcked = false;
commitAckForTrial = 0;
commitLastSendTime = NaN;
commitSendTries = 0;
pendingCommitStatus = NaN;
centerOnTime = NaN;
currentPartnerTarget = 0;
currentModeId = 0;
pendingPartnerTarget = 0;
pendingModeId = 0;
pendingOnsetKind = 0;
syncEventTrial = -1;
syncEventKind = 0;
syncEventPartnerTarget = 0;
syncEventLocalTarget = 0;
syncEventModeId = 0;
syncReadyForGo = false;
syncGoAcked = false;
syncPrepareLastSendTime = NaN;
syncPrepareSendTries = 0;
syncGoLastSendTime = NaN;
syncGoSendTries = 0;
syncGoEpochShared = NaN;
centerSyncIssuedForTrial = 0;
targetSyncIssuedForTrial = 0;
remainingPairs = zeros(0,3);
selectedTargets = DEFAULT_TARGET_SEQUENCE;
selectedModeIds = MODE_INPHASE;
errorPolicyId = ERROR_REQUEUE_TO_END;
ttlDiffThreshold = DEFAULT_TTL_DIFF_THRESHOLD;
blackScreenDurations = DEFAULT_BLACK_SCREEN_DURATIONS;
targetCircleDiameter = DEFAULT_TARGET_DIAMETER;
centerCircleDiameter = DEFAULT_CENTER_DIAMETER;
sessionConfigAcked = false;

if nargin < 1
    goalSuccesses = 100;
else
    goalSuccesses = goalSuccessesInput;
end
goalSuccessesDefault = goalSuccesses;
successCount = 0;
isServer = true;
tcpObj   = initNetwork(isServer);
screenSize = get(groot, 'ScreenSize');
trialFinalized  = false;
sessionEnding   = false;
touchCenterStartTime = NaN;
touchTargetStartTime = NaN;
targetOnTime = NaN;
centerOnTime = NaN;
localCenterHoldStartShared = NaN;
remoteCenterHoldStartShared = NaN;
trialBlackScreenChoiceIdx = 0;
trialBlackScreenDuration = NaN;
currentTarget = 0;
pendingTargetTrial  = -1;
pendingTarget       = 0;
pendingOnsetEpochShared = NaN;
pendingOnsetKind = 0;
trialFallbackTriggered = 0;
trialFallbackReason = '';
centerExitSource = CENTER_EXIT_SOURCE_NONE;
centerExitWriteTime = NaN;

runConfig = promptRunConfigCompat(makeDefaultRunConfig(goalSuccessesDefault));
if isempty(runConfig)
    sendStop();
    return;
end
applyRunConfig(runConfig);
if ~sendSessionConfigAndWait(runConfig)
    sendStop();
    return;
end
if ~performSharedClockSync()
    sendStop();
    return;
end
startTask();

    function tcpObj = initNetwork(serverFlag)
        if serverFlag
            tcpObj = tcpserver("0.0.0.0", 30000, "Timeout", 30);
            while ~tcpObj.Connected
                pause(0.01);
            end
        else
            tcpObj = [];
        end
    end

    function cfg = promptRunConfigCompat(defaultCfg)
        cfg = [];
        defaultCfg = normalizeRunConfig(defaultCfg, goalSuccessesDefault);
        targetLabels = {'1 E','2 NE','3 N','4 NW','5 W','6 SW','7 S','8 SE'};
        targetChecks = cell(1, 8);
        pageColor = [0.95, 0.96, 0.94];
        panelColor = [0.985, 0.985, 0.975];
        accentColor = [0.20, 0.45, 0.36];
        accentSoft = [0.86, 0.92, 0.89];
        textColor = [0.16, 0.18, 0.17];
        errorPolicies = [ERROR_REQUEUE_TO_END, ERROR_IMMEDIATE_REDO, ERROR_RESHUFFLE];
        errorLabels = {'Requeue To End', 'Immediate Redo', 'Reshuffle Remaining'};
        defaultErrorIdx = find(errorPolicies == defaultCfg.errorPolicyId, 1, 'first');
        if isempty(defaultErrorIdx)
            defaultErrorIdx = 1;
        end

        dlg = dialog( ...
            'Name', 'Bimanual Modes Setup', ...
            'Position', [120, 70, 820, 620], ...
            'Resize', 'on', ...
            'Color', pageColor, ...
            'CloseRequestFcn', @onCancel);
        movegui(dlg, 'center');

        uicontrol(dlg, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.04, 0.935, 0.92, 0.045], ...
            'String', 'Configure Modes After Both Sides Connect', ...
            'BackgroundColor', get(dlg, 'Color'), ...
            'ForegroundColor', textColor, ...
            'HorizontalAlignment', 'left', 'FontWeight', 'bold', 'FontSize', 15);

        uicontrol(dlg, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.04, 0.895, 0.92, 0.032], ...
            'String', 'Choose shared settings here. Left side will receive them before the 10 s startup black screen.', ...
            'BackgroundColor', get(dlg, 'Color'), ...
            'ForegroundColor', [0.34, 0.37, 0.35], ...
            'HorizontalAlignment', 'left', 'FontSize', 10.5);

        targetPanel = uipanel(dlg, 'Title', 'Target Pool', 'Units', 'normalized', ...
            'Position', [0.04, 0.41, 0.40, 0.46], 'BackgroundColor', panelColor, ...
            'FontWeight', 'bold', 'ForegroundColor', textColor);
        uicontrol(targetPanel, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.08, 0.86, 0.84, 0.07], ...
            'String', 'Click targets to include or exclude them from this session.', ...
            'BackgroundColor', get(targetPanel, 'BackgroundColor'), ...
            'ForegroundColor', [0.34, 0.37, 0.35], ...
            'HorizontalAlignment', 'left', 'FontSize', 10);
        targetPositions = [ ...
            0.70, 0.47, 0.19, 0.10; ...
            0.58, 0.64, 0.19, 0.10; ...
            0.40, 0.73, 0.19, 0.10; ...
            0.22, 0.64, 0.19, 0.10; ...
            0.10, 0.47, 0.19, 0.10; ...
            0.22, 0.30, 0.19, 0.10; ...
            0.40, 0.21, 0.19, 0.10; ...
            0.58, 0.30, 0.19, 0.10];
        uicontrol(targetPanel, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.36, 0.43, 0.28, 0.15], ...
            'String', 'CENTER', 'FontWeight', 'bold', 'FontSize', 12, ...
            'BackgroundColor', accentSoft, 'ForegroundColor', textColor);
        for idxTarget = 1:8
            targetChecks{idxTarget} = uicontrol(targetPanel, 'Style', 'togglebutton', 'Units', 'normalized', ...
                'Position', targetPositions(idxTarget,:), 'String', targetLabels{idxTarget}, ...
                'Value', ismember(idxTarget, defaultCfg.selectedTargets), ...
                'BackgroundColor', [1, 1, 1], 'FontWeight', 'bold', 'FontSize', 10.5, ...
                'ForegroundColor', textColor, 'Callback', @updateRecommendation);
        end
        uicontrol(targetPanel, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.08, 0.09, 0.26, 0.09], 'String', 'Cardinal 4', ...
            'FontWeight', 'bold', ...
            'Callback', @(~,~) setTargets([1, 3, 5, 7]));
        uicontrol(targetPanel, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.37, 0.09, 0.23, 0.09], 'String', 'All 8', ...
            'FontWeight', 'bold', ...
            'Callback', @(~,~) setTargets(1:8));
        uicontrol(targetPanel, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.63, 0.09, 0.23, 0.09], 'String', 'Clear', ...
            'FontWeight', 'bold', ...
            'Callback', @(~,~) setTargets([]));
        countLabel = uicontrol(targetPanel, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.08, 0.01, 0.84, 0.06], 'String', '', ...
            'BackgroundColor', get(targetPanel, 'BackgroundColor'), 'ForegroundColor', textColor, ...
            'HorizontalAlignment', 'left', 'FontWeight', 'bold');

        settingsPanel = uipanel(dlg, 'Title', 'Session Settings', 'Units', 'normalized', ...
            'Position', [0.47, 0.41, 0.49, 0.46], 'BackgroundColor', panelColor, ...
            'FontWeight', 'bold', 'ForegroundColor', textColor);

        makeLabel(settingsPanel, [0.05, 0.86, 0.90, 0.08], 'Modes', true);
        cbIn = uicontrol(settingsPanel, 'Style', 'checkbox', 'Units', 'normalized', ...
            'Position', [0.05, 0.78, 0.90, 0.07], 'String', 'Inphase (same direction)', ...
            'Value', any(defaultCfg.selectedModes == MODE_INPHASE), ...
            'BackgroundColor', get(settingsPanel, 'BackgroundColor'), 'Callback', @updateRecommendation);
        cbAnti = uicontrol(settingsPanel, 'Style', 'checkbox', 'Units', 'normalized', ...
            'Position', [0.05, 0.70, 0.90, 0.07], 'String', 'Antiphase (opposite direction)', ...
            'Value', any(defaultCfg.selectedModes == MODE_ANTIPHASE), ...
            'BackgroundColor', get(settingsPanel, 'BackgroundColor'), 'Callback', @updateRecommendation);
        cbQuarter = uicontrol(settingsPanel, 'Style', 'checkbox', 'Units', 'normalized', ...
            'Position', [0.05, 0.62, 0.90, 0.07], 'String', '90deg phase (cw and ccw)', ...
            'Value', any(defaultCfg.selectedModes == MODE_QUARTER), ...
            'BackgroundColor', get(settingsPanel, 'BackgroundColor'), 'Callback', @updateRecommendation);

        makeLabel(settingsPanel, [0.05, 0.52, 0.42, 0.06], 'Goal successes', false);
        goalField = uicontrol(settingsPanel, 'Style', 'edit', 'Units', 'normalized', ...
            'Position', [0.52, 0.53, 0.38, 0.06], 'String', num2str(defaultCfg.goalSuccesses), ...
            'BackgroundColor', 'white', 'Callback', @updateRecommendation);
        makeLabel(settingsPanel, [0.05, 0.44, 0.42, 0.06], 'TTL diff threshold (s)', false);
        ttlField = uicontrol(settingsPanel, 'Style', 'edit', 'Units', 'normalized', ...
            'Position', [0.52, 0.45, 0.38, 0.06], 'String', num2str(defaultCfg.ttlDiffThreshold, '%.3f'), ...
            'BackgroundColor', 'white', 'Callback', @updateRecommendation);
        makeLabel(settingsPanel, [0.05, 0.36, 0.42, 0.06], 'Error handling', false);
        errMenu = uicontrol(settingsPanel, 'Style', 'popupmenu', 'Units', 'normalized', ...
            'Position', [0.52, 0.37, 0.38, 0.06], 'String', errorLabels, 'Value', defaultErrorIdx, ...
            'BackgroundColor', 'white', 'Callback', @updateRecommendation);
        makeLabel(settingsPanel, [0.05, 0.28, 0.42, 0.06], 'Target circle diameter', false);
        targetDiameterField = uicontrol(settingsPanel, 'Style', 'edit', 'Units', 'normalized', ...
            'Position', [0.52, 0.29, 0.38, 0.06], 'String', num2str(defaultCfg.targetCircleDiameter, '%.3f'), ...
            'BackgroundColor', 'white', 'Callback', @updateRecommendation);
        makeLabel(settingsPanel, [0.05, 0.20, 0.42, 0.06], 'Center circle diameter', false);
        centerDiameterField = uicontrol(settingsPanel, 'Style', 'edit', 'Units', 'normalized', ...
            'Position', [0.52, 0.21, 0.38, 0.06], 'String', num2str(defaultCfg.centerCircleDiameter, '%.3f'), ...
            'BackgroundColor', 'white', 'Callback', @updateRecommendation);
        makeLabel(settingsPanel, [0.05, 0.12, 0.85, 0.06], 'Trial black-screen durations (comma-separated seconds)', false);
        blackField = uicontrol(settingsPanel, 'Style', 'edit', 'Units', 'normalized', ...
            'Position', [0.05, 0.05, 0.85, 0.06], 'String', formatDurationList(defaultCfg.blackScreenDurations), ...
            'BackgroundColor', 'white', 'Callback', @updateRecommendation);

        uicontrol(dlg, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.04, 0.355, 0.92, 0.04], ...
            'String', 'Startup stays at 10 s. These values only control the trial-to-trial black screen.', ...
            'BackgroundColor', get(dlg, 'Color'), 'ForegroundColor', [0.34, 0.37, 0.35], ...
            'HorizontalAlignment', 'left', 'FontAngle', 'italic', 'FontSize', 10);

        summaryBox = uicontrol(dlg, 'Style', 'edit', 'Units', 'normalized', ...
            'Position', [0.04, 0.13, 0.92, 0.20], 'Max', 20, 'Min', 0, 'Enable', 'inactive', ...
            'HorizontalAlignment', 'left', 'BackgroundColor', [0.985, 0.985, 0.975], ...
            'ForegroundColor', textColor, 'FontName', 'Consolas', 'FontSize', 11, 'String', '');
        statusLabel = uicontrol(dlg, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.04, 0.05, 0.46, 0.055], 'String', '', ...
            'BackgroundColor', get(dlg, 'Color'), 'ForegroundColor', textColor, ...
            'HorizontalAlignment', 'left', 'FontWeight', 'bold');
        startButton = uicontrol(dlg, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.54, 0.045, 0.16, 0.07], 'String', 'Confirm & Start', ...
            'FontWeight', 'bold', 'FontSize', 11, 'BackgroundColor', accentColor, ...
            'ForegroundColor', [1, 1, 1], 'Callback', @onStart);
        uicontrol(dlg, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.72, 0.045, 0.14, 0.07], 'String', 'Reset Defaults', ...
            'FontWeight', 'bold', 'Callback', @onReset);
        uicontrol(dlg, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.88, 0.045, 0.08, 0.07], 'String', 'Cancel', ...
            'FontWeight', 'bold', 'Callback', @onCancel);

        updateRecommendation();
        uiwait(dlg);

        function makeLabel(parentHandle, pos, labelText, isBold)
            if nargin < 4
                isBold = false;
            end
            fontWeight = 'normal';
            if isBold
                fontWeight = 'bold';
            end
            uicontrol(parentHandle, 'Style', 'text', 'Units', 'normalized', ...
                'Position', pos, 'String', labelText, ...
                'BackgroundColor', get(parentHandle, 'BackgroundColor'), ...
                'ForegroundColor', textColor, ...
                'HorizontalAlignment', 'left', 'FontWeight', fontWeight, 'FontSize', 10.5);
        end

        function txt = formatDurationList(vals)
            parts = arrayfun(@(v) sprintf('%.3g', v), vals, 'UniformOutput', false);
            txt = strjoin(parts, ', ');
        end

        function lines = roundSuggestionLines(goalVal, blockSize)
            lines = {};
            if ~(isfinite(goalVal) && goalVal > 0 && blockSize > 0)
                return;
            end
            goalVal = round(goalVal);
            fullRounds = floor(goalVal / blockSize);
            remainderTrials = mod(goalVal, blockSize);
            lowerRounds = max(1, floor(goalVal / blockSize));
            upperRounds = max(1, ceil(goalVal / blockSize));

            lines{end+1} = sprintf('1 full round = %d successful trials (all valid combinations once).', blockSize);
            if remainderTrials == 0
                lines{end+1} = sprintf('Current design: %d rounds = %d successes exactly.', fullRounds, goalVal);
            else
                lines{end+1} = sprintf('Current design: %d full rounds + %d extra successes.', fullRounds, remainderTrials);
                if lowerRounds == upperRounds
                    lines{end+1} = sprintf('Suggested balanced design: %d rounds = %d successes.', upperRounds, upperRounds * blockSize);
                else
                    lines{end+1} = sprintf('Suggested balanced designs: %d rounds = %d or %d rounds = %d successes.', ...
                        lowerRounds, lowerRounds * blockSize, upperRounds, upperRounds * blockSize);
                end
            end
        end

        function selectedTargetIds = getSelectedTargets()
            selectedTargetIds = [];
            for localIdx = 1:8
                if get(targetChecks{localIdx}, 'Value')
                    selectedTargetIds(end+1) = localIdx; %#ok<AGROW>
                end
            end
        end

        function modeIds = getSelectedModes()
            modeIds = [];
            if get(cbIn, 'Value'), modeIds(end+1) = MODE_INPHASE; end
            if get(cbAnti, 'Value'), modeIds(end+1) = MODE_ANTIPHASE; end
            if get(cbQuarter, 'Value'), modeIds(end+1) = MODE_QUARTER; end
        end

        function policyId = getSelectedErrorPolicy()
            policyId = errorPolicies(get(errMenu, 'Value'));
        end

        function [val, ok] = parsePositiveScalar(editHandle)
            val = str2double(strtrim(get(editHandle, 'String')));
            ok = isfinite(val) && val > 0;
        end

        function setTargets(targetIds)
            targetIds = unique(targetIds(:).');
            for localIdx = 1:8
                set(targetChecks{localIdx}, 'Value', ismember(localIdx, targetIds));
            end
            refreshTargetButtons();
            updateRecommendation();
        end

        function refreshTargetButtons()
            for localIdx = 1:8
                if get(targetChecks{localIdx}, 'Value')
                    set(targetChecks{localIdx}, 'BackgroundColor', accentColor, 'ForegroundColor', [1, 1, 1]);
                else
                    set(targetChecks{localIdx}, 'BackgroundColor', [1, 1, 1], 'ForegroundColor', textColor);
                end
            end
        end

        function updateSummaryBox(lines)
            set(summaryBox, 'String', lines(:));
        end

        function updateRecommendation(~,~)
            refreshTargetButtons();
            selectedTargetsLocal = getSelectedTargets();
            modeIds = getSelectedModes();
            blockSize = computeBlockSize(selectedTargetsLocal, modeIds);
            [goalVal, goalOk] = parsePositiveScalar(goalField);
            [ttlVal, ttlOk] = parsePositiveScalar(ttlField);
            [targetDia, targetDiaOk] = parsePositiveScalar(targetDiameterField);
            [centerDia, centerDiaOk] = parsePositiveScalar(centerDiameterField);
            validationIssue = '';

            if isempty(selectedTargetsLocal)
                validationIssue = 'Select at least one target.';
            elseif isempty(modeIds)
                validationIssue = 'Select at least one mode.';
            elseif blockSize <= 0
                validationIssue = 'This target/mode selection creates no valid target pairs.';
            elseif ~goalOk
                validationIssue = 'Goal successes must be positive.';
            elseif ~ttlOk
                validationIssue = 'TTL diff threshold must be positive.';
            elseif ~targetDiaOk
                validationIssue = 'Target diameter must be positive.';
            elseif ~centerDiaOk
                validationIssue = 'Center diameter must be positive.';
            else
                try
                    parseDurationList(get(blackField, 'String'));
                catch ME
                    validationIssue = ME.message;
                end
            end

            set(countLabel, 'String', sprintf('Selected targets (%d): %s', numel(selectedTargetsLocal), mat2str(selectedTargetsLocal)));

            summaryLines = { ...
                '=== Selection ===', ...
                sprintf('Targets (%d): %s', numel(selectedTargetsLocal), mat2str(selectedTargetsLocal)), ...
                sprintf('Modes: %s', modeIdsToText(modeIds)), ...
                sprintf('Error handling: %s', errorLabels{get(errMenu, 'Value')}), ...
                ' ', ...
                '=== Balance ===', ...
                sprintf('Valid trial combinations per full round: %d', blockSize)};
            if goalOk && blockSize > 0
                goalVal = round(goalVal);
                roundLines = roundSuggestionLines(goalVal, blockSize);
                summaryLines = [summaryLines, roundLines];
            end
            summaryLines{end+1} = ' ';
            summaryLines{end+1} = '=== Timing & Size ===';
            if ttlOk && targetDiaOk && centerDiaOk
                summaryLines{end+1} = sprintf('TTL threshold: %.3f s | Target dia: %.3f | Center dia: %.3f', ttlVal, targetDia, centerDia);
            end
            summaryLines{end+1} = sprintf('Trial black screens: %s s', get(blackField, 'String'));
            summaryLines{end+1} = ' ';
            summaryLines{end+1} = '=== Sync ===';
            summaryLines{end+1} = 'Right side will send this session design to the left side before the startup black screen.';
            updateSummaryBox(summaryLines);

            if isempty(validationIssue)
                set(statusLabel, 'String', 'Ready to sync settings to the left side.', 'ForegroundColor', [0.18, 0.42, 0.27]);
                set(startButton, 'Enable', 'on');
            else
                set(statusLabel, 'String', validationIssue, 'ForegroundColor', [0.72, 0.2, 0.16]);
                set(startButton, 'Enable', 'off');
            end
        end

        function onReset(~,~)
            setTargets(defaultCfg.selectedTargets);
            set(cbIn, 'Value', any(defaultCfg.selectedModes == MODE_INPHASE));
            set(cbAnti, 'Value', any(defaultCfg.selectedModes == MODE_ANTIPHASE));
            set(cbQuarter, 'Value', any(defaultCfg.selectedModes == MODE_QUARTER));
            set(goalField, 'String', num2str(defaultCfg.goalSuccesses));
            set(ttlField, 'String', num2str(defaultCfg.ttlDiffThreshold, '%.3f'));
            set(errMenu, 'Value', defaultErrorIdx);
            set(targetDiameterField, 'String', num2str(defaultCfg.targetCircleDiameter, '%.3f'));
            set(centerDiameterField, 'String', num2str(defaultCfg.centerCircleDiameter, '%.3f'));
            set(blackField, 'String', formatDurationList(defaultCfg.blackScreenDurations));
            updateRecommendation();
        end

        function onCancel(~,~)
            cfg = [];
            if ishghandle(dlg)
                uiresume(dlg);
                delete(dlg);
            end
        end

        function onStart(~,~)
            selectedTargetsLocal = getSelectedTargets();
            modeIds = getSelectedModes();
            [goalVal, goalOk] = parsePositiveScalar(goalField);
            [ttlVal, ttlOk] = parsePositiveScalar(ttlField);
            [targetDia, targetDiaOk] = parsePositiveScalar(targetDiameterField);
            [centerDia, centerDiaOk] = parsePositiveScalar(centerDiameterField);

            if isempty(selectedTargetsLocal)
                errordlg('Select at least one target.', 'Target selection', 'modal');
                return;
            end
            if isempty(modeIds)
                errordlg('Select at least one mode.', 'Mode selection', 'modal');
                return;
            end
            if ~goalOk
                errordlg('Goal successes must be positive.', 'Goal successes', 'modal');
                return;
            end
            if ~ttlOk
                errordlg('TTL diff threshold must be positive.', 'TTL threshold', 'modal');
                return;
            end
            if ~targetDiaOk
                errordlg('Target diameter must be positive.', 'Target diameter', 'modal');
                return;
            end
            if ~centerDiaOk
                errordlg('Center diameter must be positive.', 'Center diameter', 'modal');
                return;
            end

            try
                blackDurations = parseDurationList(get(blackField, 'String'));
            catch ME
                errordlg(ME.message, 'Black-screen durations', 'modal');
                return;
            end

            draftCfg = struct( ...
                'goalSuccesses', round(goalVal), ...
                'selectedTargets', selectedTargetsLocal, ...
                'selectedModes', modeIds, ...
                'errorPolicyId', getSelectedErrorPolicy(), ...
                'ttlDiffThreshold', ttlVal, ...
                'blackScreenDurations', blackDurations, ...
                'targetCircleDiameter', targetDia, ...
                'centerCircleDiameter', centerDia);
            draftCfg = normalizeRunConfig(draftCfg, goalSuccessesDefault);
            blockSize = computeBlockSize(draftCfg.selectedTargets, draftCfg.selectedModes);
            if blockSize <= 0
                errordlg('This target and mode selection creates no valid target pairs.', 'No valid pairs', 'modal');
                return;
            end
            if mod(draftCfg.goalSuccesses, blockSize) ~= 0
                lowerRounds = max(1, floor(draftCfg.goalSuccesses / blockSize));
                upperRounds = max(1, ceil(draftCfg.goalSuccesses / blockSize));
                choice = questdlg( ...
                    sprintf(['Current goal %d is not a multiple of the balanced block size %d.\n' ...
                             'That means %d full rounds + %d extra successes.\n' ...
                             'Suggested balanced designs: %d rounds = %d or %d rounds = %d successes.\n' ...
                             'The final successful trials will not be perfectly balanced.\n' ...
                             'Use this value anyway?'], ...
                             draftCfg.goalSuccesses, blockSize, ...
                             floor(draftCfg.goalSuccesses / blockSize), mod(draftCfg.goalSuccesses, blockSize), ...
                             lowerRounds, lowerRounds * blockSize, upperRounds, upperRounds * blockSize), ...
                    'Unbalanced Goal Successes', 'Use Anyway', 'Go Back', 'Go Back');
                if ~strcmp(choice, 'Use Anyway')
                    return;
                end
            end

            cfg = draftCfg;
            if ishghandle(dlg)
                uiresume(dlg);
                delete(dlg);
            end
        end
    end

    function ok = safeWrite(obj, data, dtype, tag)
        ok = true;
        for k = 1:3
            try
                write(obj, data, dtype);
                return;
            catch ME
                ok = false;
                warning('[%s] write failed (%d): %s', tag, k, ME.message);
                pause(0.002);
            end
        end
    end

    function pumpNetwork()
        if isempty(tcpObj) || ~isvalid(tcpObj), return; end
        n = tcpObj.NumBytesAvailable;
        if n <= 0, return; end
        bytes = read(tcpObj, n, 'uint8');
        if isempty(bytes), return; end
        rxbuf = [rxbuf; bytes(:)];
    end

    function t = nowMonotonic()
        t = toc(syncClock);
    end

    function t = nowShared()
        t = nowMonotonic() + clockOffsetToShared;
    end

    function t = nowTrial()
        if isnan(trialStartEpochShared)
            t = NaN;
        else
            t = nowShared() - trialStartEpochShared;
        end
    end

    function L = payloadLen(op_)
        switch op_
            case OP_TARGET_DONE, L = 18;
            case OP_FAIL,        L = 3;
            case OP_CENTER_DONE, L = 2;
            case OP_CENTER_ACK,  L = 2;
            case OP_COMMIT,      L = 4;
            case OP_TARGET_DONE_ACK, L = 2;
            case OP_READY,       L = 0;
            case OP_DONE,        L = 0;
            case OP_COMMIT_ACK,  L = 2;
            case OP_PREPARE_ONSET, L = 6;
            case OP_READY_FOR_GO,  L = 3;
            case OP_GO_CUE,        L = 11;
            case OP_GO_ACK,        L = 3;
            case OP_CLOCK_SYNC_REQ,   L = 10;
            case OP_CLOCK_SYNC_REPLY, L = 18;
            case OP_CLOCK_SYNC_SET,   L = 10;
            case OP_CLOCK_SYNC_ACK,   L = 2;
            case OP_SESSION_CONFIG_ACK, L = 0;
            case OP_CENTER_HOLD_START, L = 10;
            case OP_CENTER_HOLD_START_ACK, L = 2;
            case OP_STOP,        L = 0;
            otherwise,           L = 0;
        end
    end

    function cfg = makeDefaultRunConfig(defaultGoal)
        cfg = struct( ...
            'goalSuccesses', round(defaultGoal), ...
            'selectedTargets', DEFAULT_TARGET_SEQUENCE, ...
            'selectedModes', MODE_INPHASE, ...
            'errorPolicyId', ERROR_REQUEUE_TO_END, ...
            'ttlDiffThreshold', DEFAULT_TTL_DIFF_THRESHOLD, ...
            'blackScreenDurations', DEFAULT_BLACK_SCREEN_DURATIONS, ...
            'targetCircleDiameter', DEFAULT_TARGET_DIAMETER, ...
            'centerCircleDiameter', DEFAULT_CENTER_DIAMETER);
    end

    function cfg = normalizeRunConfig(cfg, defaultGoal)
        defaultCfg = makeDefaultRunConfig(defaultGoal);
        if ~isstruct(cfg)
            cfg = defaultCfg;
            return;
        end

        if ~isfield(cfg,'goalSuccesses'), cfg.goalSuccesses = defaultCfg.goalSuccesses; end
        if ~isfield(cfg,'selectedTargets'), cfg.selectedTargets = defaultCfg.selectedTargets; end
        if ~isfield(cfg,'selectedModes'), cfg.selectedModes = defaultCfg.selectedModes; end
        if ~isfield(cfg,'errorPolicyId'), cfg.errorPolicyId = defaultCfg.errorPolicyId; end
        if ~isfield(cfg,'ttlDiffThreshold'), cfg.ttlDiffThreshold = defaultCfg.ttlDiffThreshold; end
        if ~isfield(cfg,'blackScreenDurations'), cfg.blackScreenDurations = defaultCfg.blackScreenDurations; end
        if ~isfield(cfg,'targetCircleDiameter'), cfg.targetCircleDiameter = defaultCfg.targetCircleDiameter; end
        if ~isfield(cfg,'centerCircleDiameter'), cfg.centerCircleDiameter = defaultCfg.centerCircleDiameter; end

        goalVal = round(double(cfg.goalSuccesses));
        if ~isfinite(goalVal) || goalVal <= 0
            goalVal = defaultCfg.goalSuccesses;
        end

        selectedTargetsLocal = sort(unique(round(double(cfg.selectedTargets(:).'))));
        selectedTargetsLocal = selectedTargetsLocal(selectedTargetsLocal >= 1 & selectedTargetsLocal <= 8);
        if isempty(selectedTargetsLocal)
            selectedTargetsLocal = defaultCfg.selectedTargets;
        end

        modeIds = sort(unique(round(double(cfg.selectedModes(:).'))));
        modeIds = modeIds(ismember(modeIds, [MODE_INPHASE, MODE_ANTIPHASE, MODE_QUARTER]));
        if isempty(modeIds)
            modeIds = defaultCfg.selectedModes;
        end

        errorPolicy = round(double(cfg.errorPolicyId));
        if ~ismember(errorPolicy, [ERROR_REQUEUE_TO_END, ERROR_IMMEDIATE_REDO, ERROR_RESHUFFLE])
            errorPolicy = defaultCfg.errorPolicyId;
        end

        ttlThreshold = double(cfg.ttlDiffThreshold);
        if ~isfinite(ttlThreshold) || ttlThreshold <= 0
            ttlThreshold = defaultCfg.ttlDiffThreshold;
        end

        blackDurations = double(cfg.blackScreenDurations(:).');
        blackDurations = blackDurations(isfinite(blackDurations) & blackDurations > 0);
        if isempty(blackDurations)
            blackDurations = defaultCfg.blackScreenDurations;
        end
        if numel(blackDurations) > 255
            blackDurations = blackDurations(1:255);
        end

        targetDia = double(cfg.targetCircleDiameter);
        if ~isfinite(targetDia) || targetDia <= 0
            targetDia = defaultCfg.targetCircleDiameter;
        end

        centerDia = double(cfg.centerCircleDiameter);
        if ~isfinite(centerDia) || centerDia <= 0
            centerDia = defaultCfg.centerCircleDiameter;
        end

        cfg = struct( ...
            'goalSuccesses', goalVal, ...
            'selectedTargets', selectedTargetsLocal, ...
            'selectedModes', modeIds, ...
            'errorPolicyId', errorPolicy, ...
            'ttlDiffThreshold', ttlThreshold, ...
            'blackScreenDurations', blackDurations, ...
            'targetCircleDiameter', targetDia, ...
            'centerCircleDiameter', centerDia);
    end

    function applyRunConfig(cfg)
        cfg = normalizeRunConfig(cfg, goalSuccessesDefault);
        goalSuccesses = cfg.goalSuccesses;
        selectedTargets = cfg.selectedTargets;
        selectedModeIds = cfg.selectedModes;
        errorPolicyId = cfg.errorPolicyId;
        ttlDiffThreshold = cfg.ttlDiffThreshold;
        blackScreenDurations = cfg.blackScreenDurations;
        targetCircleDiameter = cfg.targetCircleDiameter;
        centerCircleDiameter = cfg.centerCircleDiameter;
    end

    function blockSize = computeBlockSize(targetIds, modeIds)
        blockSize = size(buildTrialPairs(targetIds, modeIds, false), 1);
    end

    function txt = modeIdsToText(modeIds)
        labels = strings(0,1);
        if any(modeIds == MODE_INPHASE), labels(end+1) = "Inphase"; end
        if any(modeIds == MODE_ANTIPHASE), labels(end+1) = "Antiphase"; end
        if any(modeIds == MODE_QUARTER), labels(end+1) = "90deg"; end
        if isempty(labels)
            txt = 'None';
        else
            txt = strjoin(cellstr(labels), ', ');
        end
    end

    function tag = modeIdsToFileTag(modeIds)
        parts = strings(0,1);
        if any(modeIds == MODE_INPHASE), parts(end+1) = "inphase"; end
        if any(modeIds == MODE_ANTIPHASE), parts(end+1) = "antiphase"; end
        if any(modeIds == MODE_QUARTER), parts(end+1) = "90deg"; end
        if isempty(parts)
            tag = 'none';
        else
            tag = strjoin(cellstr(parts), '-');
        end
    end

    function tag = errorPolicyToFileTag(policyId)
        switch policyId
            case ERROR_REQUEUE_TO_END
                tag = 'requeue_to_end';
            case ERROR_IMMEDIATE_REDO
                tag = 'immediate_redo';
            case ERROR_RESHUFFLE
                tag = 'reshuffle_remaining';
            otherwise
                tag = 'unknown_policy';
        end
    end

    function tag = sessionSaveTag()
        tag = sprintf('modes_%s_redo_%s', modeIdsToFileTag(selectedModeIds), errorPolicyToFileTag(errorPolicyId));
    end

    function vals = parseDurationList(rawText)
        if isstring(rawText)
            rawText = char(rawText);
        end
        if isempty(rawText)
            error('Black-screen durations cannot be empty.');
        end
        tokens = regexp(rawText, '[,\s;]+', 'split');
        tokens = tokens(~cellfun('isempty', tokens));
        vals = str2double(tokens);
        if isempty(vals) || any(~isfinite(vals)) || any(vals <= 0)
            error('Enter black-screen durations like 5, 5.5, 6.');
        end
        if numel(vals) > 255
            error('Use at most 255 black-screen duration candidates.');
        end
        vals = vals(:).';
    end

    function packet = encodeSessionConfig(cfg)
        cfg = normalizeRunConfig(cfg, goalSuccessesDefault);
        jsonBytes = uint8(unicode2native(jsonencode(cfg), 'UTF-8'));
        packet = [uint8(OP_SESSION_CONFIG), typecast(uint16(numel(jsonBytes)), 'uint8'), jsonBytes];
    end

    function ok = sendSessionConfigAndWait(cfg)
        ok = false;
        packet = encodeSessionConfig(cfg);
        sessionConfigAcked = false;
        syncStart = tic;
        lastSend = -inf;
        sendCount = 0;
        while ~sessionConfigAcked
            if sessionEnding, return; end
            nowRel = toc(syncStart);
            if sendCount == 0 || (nowRel - lastSend) >= 0.25
                safeWrite(tcpObj, packet, 'uint8', 'SESSION_CONFIG');
                lastSend = nowRel;
                sendCount = sendCount + 1;
            end
            processRx();
            if sessionConfigAcked
                ok = true;
                return;
            end
            if nowRel > 30
                warning('Timed out waiting for session-configuration acknowledgement.');
                return;
            end
            pause(0.01);
        end
        ok = true;
    end

    function ok = performSharedClockSync()
        ok = false;
        bestOffset = NaN;
        bestRtt = inf;

        for seq = 1:CLOCK_SYNC_SAMPLE_COUNT
            clockSyncReplySeq = -1;
            clockSyncReplyMasterSend = NaN;
            clockSyncReplyRemoteMono = NaN;
            masterSend = nowMonotonic();
            payload = [ ...
                uint8(OP_CLOCK_SYNC_REQ), ...
                typecast(uint16(seq), 'uint8'), ...
                typecast(masterSend, 'uint8') ...
                ];
            safeWrite(tcpObj, payload, 'uint8', 'CLOCK_SYNC_REQ');

            waitStart = nowMonotonic();
            while (nowMonotonic() - waitStart) < CLOCK_SYNC_REPLY_TIMEOUT
                if sessionEnding
                    return;
                end
                processRx();
                if clockSyncReplySeq == seq
                    masterRecv = nowMonotonic();
                    rtt = masterRecv - clockSyncReplyMasterSend;
                    offsetEstimate = ((clockSyncReplyMasterSend + masterRecv) / 2) - clockSyncReplyRemoteMono;
                    if rtt < bestRtt
                        bestRtt = rtt;
                        bestOffset = offsetEstimate;
                    end
                    break;
                end
                pause(0.001);
            end
        end

        if isnan(bestOffset)
            warning('Shared clock sync failed: no reply sample received.');
            return;
        end

        clockSyncSetSeq = CLOCK_SYNC_SAMPLE_COUNT + 1;
        clockSyncSetAcked = false;
        payload = [ ...
            uint8(OP_CLOCK_SYNC_SET), ...
            typecast(uint16(clockSyncSetSeq), 'uint8'), ...
            typecast(bestOffset, 'uint8') ...
            ];
        safeWrite(tcpObj, payload, 'uint8', 'CLOCK_SYNC_SET');

        waitStart = nowMonotonic();
        while ~clockSyncSetAcked
            if sessionEnding
                return;
            end
            processRx();
            if (nowMonotonic() - waitStart) > CLOCK_SYNC_SET_TIMEOUT
                warning('Timed out waiting for shared clock sync acknowledgement.');
                return;
            end
            pause(0.001);
        end

        clockOffsetToShared = 0;
        ok = true;
    end

    function forceStop()
        if sessionEnding, return; end
        sessionEnding = true;
        try
            if ~isempty(timerObj) && isvalid(timerObj)
                stop(timerObj);
                delete(timerObj);
            end
        catch
        end
        try
            if ~isempty(fig) && isvalid(fig)
                close(fig);
            end
        catch
        end
    end

    function sendCommitPacket(trialNum, statusCode, tag)
        ensureTrialBlackScreenChoice();
        payload = [uint8(OP_COMMIT), typecast(uint16(trialNum),'uint8'), uint8(statusCode), uint8(trialBlackScreenChoiceIdx)];
        safeWrite(tcpObj, payload, 'uint8', tag);
        commitLastSendTime = nowMonotonic();
        commitSendTries = commitSendTries + 1;
    end

    function sendCommit(trialNum, statusCode)
        pendingCommitStatus = statusCode;
        commitAckForTrial = 0;
        commitLastSendTime = NaN;
        commitSendTries = 0;
        sendCommitPacket(trialNum, statusCode, 'COMMIT');
    end

    function sendStop()
        safeWrite(tcpObj, uint8(OP_STOP), 'uint8', 'STOP');
    end

    function out = rotateTargets(targets, step45)
        out = mod(targets - 1 + step45, 8) + 1;
    end

    function pairs = buildTrialPairs(baseTargets, modeIds, shufflePairs)
        if nargin < 3
            shufflePairs = true;
        end
        selectedSet = unique(baseTargets(:));
        leftTargets = selectedSet(:);
        pairs = zeros(0,3);
        if any(modeIds == MODE_INPHASE)
            pairs = [pairs; [leftTargets, leftTargets, MODE_INPHASE * ones(numel(leftTargets),1)]];
        end
        if any(modeIds == MODE_ANTIPHASE)
            antiTargets = rotateTargets(leftTargets, 4);
            keepMask = ismember(antiTargets, selectedSet);
            pairs = [pairs; [leftTargets(keepMask), antiTargets(keepMask), MODE_ANTIPHASE * ones(nnz(keepMask),1)]];
        end
        if any(modeIds == MODE_QUARTER)
            quarterPlusTargets = rotateTargets(leftTargets, 2);
            keepPlus = ismember(quarterPlusTargets, selectedSet);
            pairs = [pairs; [leftTargets(keepPlus), quarterPlusTargets(keepPlus), MODE_QUARTER * ones(nnz(keepPlus),1)]];
            quarterMinusTargets = rotateTargets(leftTargets, -2);
            keepMinus = ismember(quarterMinusTargets, selectedSet);
            pairs = [pairs; [leftTargets(keepMinus), quarterMinusTargets(keepMinus), MODE_QUARTER * ones(nnz(keepMinus),1)]];
        end
        if shufflePairs && ~isempty(pairs)
            pairs = pairs(randperm(size(pairs,1)), :);
        end
    end

    function updateRemainingTargetsAfterTrial(statusCode)
        if currentTarget <= 0 || isempty(remainingPairs)
            return;
        end

        key = [currentPartnerTarget, currentTarget, currentModeId];
        idx = find(all(remainingPairs == key, 2), 1, 'first');
        if isempty(idx)
            return;
        end

        if statusCode == STATUS_SUCCESS
            remainingPairs(idx,:) = [];
        else
            switch errorPolicyId
                case ERROR_REQUEUE_TO_END
                    pairRow = remainingPairs(idx,:);
                    remainingPairs(idx,:) = [];
                    remainingPairs(end+1,:) = pairRow;
                case ERROR_IMMEDIATE_REDO
                    % Keep the current pair at the front of the queue.
                case ERROR_RESHUFFLE
                    remainingPairs = remainingPairs(randperm(size(remainingPairs,1)), :);
            end
        end
    end

    function processRx()
        pumpNetwork();
        while true
            if sessionEnding, return; end
            if numel(rxbuf) < 1, break; end
            op = rxbuf(1);
            if op == OP_SESSION_CONFIG
                if numel(rxbuf) < 3
                    break;
                end
                need = double(typecast(uint8(rxbuf(2:3)), 'uint16'));
                if numel(rxbuf) < 3 + need
                    break;
                end
                payload = rxbuf(4 : 3 + need);
                rxbuf   = rxbuf(4 + need : end);
            else
                need = payloadLen(op);
                if numel(rxbuf) < 1 + need
                    break;
                end
                payload = rxbuf(2 : 1 + need);
                rxbuf   = rxbuf(2 + need : end);
            end

            switch op
                case OP_READY
                    barrierRemoteReady = true;

                case OP_DONE
                    barrierRemoteDone  = true;

                case OP_STOP
                    forceStop();
                    return;

                case OP_CENTER_DONE
                    rTrial = double(typecast(uint8(payload(1:2)), 'uint16'));
                    safeWrite(tcpObj, [uint8(OP_CENTER_ACK), typecast(uint16(rTrial),'uint8')], 'uint8', 'ACK');
                    if rTrial > remoteCenterIdx
                        remoteCenterIdx = rTrial;
                    end

                case OP_CENTER_HOLD_START
                    rTrial = double(typecast(uint8(payload(1:2)), 'uint16'));
                    holdStartShared = double(typecast(uint8(payload(3:10)), 'double'));
                    safeWrite(tcpObj, [uint8(OP_CENTER_HOLD_START_ACK), typecast(uint16(rTrial),'uint8')], 'uint8', 'CENTER_HOLD_START_ACK');
                    if rTrial == trialIndex && ~trialFinalized
                        remoteCenterHoldStartShared = holdStartShared;
                        maybeDriveOnsetSync();
                    end

                case OP_CENTER_ACK
                    ackIdx = double(typecast(uint8(payload(1:2)), 'uint16'));
                    if ackIdx == trialIndex
                        awaitingAck4 = false;
                    end

                case OP_TARGET_DONE
                    rTrial = double(typecast(uint8(payload(1:2)), 'uint16'));
                    safeWrite(tcpObj, [uint8(OP_TARGET_DONE_ACK), typecast(uint16(rTrial),'uint8')], 'uint8', 'TARGET_DONE_ACK');
                    if rTrial ~= trialIndex
                        continue;
                    end
                    times = typecast(uint8(payload(3:end)), 'double');
                    remoteTtlFirst = times(1);
                    remoteTtlEnd   = times(2);
                    remoteSuccess  = true;
                    if localSuccess && ~trialFinalized
                        decideAndCommit();
                    end

                case OP_TARGET_DONE_ACK
                    % Right side only acknowledges TARGET_DONE packets.

                case OP_COMMIT_ACK
                    ackTrial = double(typecast(uint8(payload(1:2)), 'uint16'));
                    if ackTrial == trialIndex
                        commitAckForTrial = ackTrial;
                    end

                case OP_SESSION_CONFIG_ACK
                    sessionConfigAcked = true;

                case OP_CLOCK_SYNC_REPLY
                    rSeq = double(typecast(uint8(payload(1:2)), 'uint16'));
                    vals = typecast(uint8(payload(3:end)), 'double');
                    clockSyncReplySeq = rSeq;
                    clockSyncReplyMasterSend = vals(1);
                    clockSyncReplyRemoteMono = vals(2);

                case OP_CLOCK_SYNC_ACK
                    rSeq = double(typecast(uint8(payload(1:2)), 'uint16'));
                    if rSeq == clockSyncSetSeq
                        clockSyncSetAcked = true;
                    end

                case OP_READY_FOR_GO
                    rTrial = double(typecast(uint8(payload(1:2)), 'uint16'));
                    eventKind = double(payload(3));
                    if rTrial == syncEventTrial && eventKind == syncEventKind
                        syncReadyForGo = true;
                    end

                case OP_GO_ACK
                    rTrial = double(typecast(uint8(payload(1:2)), 'uint16'));
                    eventKind = double(payload(3));
                    if rTrial == syncEventTrial && eventKind == syncEventKind
                        syncGoAcked = true;
                    end

                case OP_FAIL
                    rTrial = double(typecast(uint8(payload(1:2)), 'uint16'));
                    st     = double(payload(3));
                    if rTrial ~= trialIndex
                        continue;
                    end
                    if ~trialFinalized
                        sendCommit(trialIndex, st);
                        finalizeTrial(st);
                    end

                otherwise
            end
        end
    end

    function showBlackPanelScreenSync(duration)
        if sessionEnding, return; end
        barrierRemoteReady = false;
        barrierRemoteDone  = false;
        barrierLocalReady  = false;
        barrierLocalDone   = false;
        safeWrite(tcpObj, uint8(OP_READY), 'uint8', 'READY');
        barrierLocalReady = true;

        tWait = tic;
        while ~barrierRemoteReady
            if sessionEnding, break; end
            processRx();
            retryCommitIfNeeded();
            if toc(tWait) > 5
                markTrialFallback('BLACK_READY_TIMEOUT');
                break;
            end
            pause(0.001);
        end

        if sessionEnding
            return;
        end

        origCol = get(fig,'Color');
        origUnit = get(fig,'Units');
        origWin = get(fig,'WindowState');
        set(fig,'WindowState','fullscreen');
        blk = uipanel('Parent',fig,'Units','normalized','Position',[0 0 1 1], ...
            'BackgroundColor','black','BorderType','none');
        drawnow;
        set(fig,'WindowButtonMotionFcn','');

        t0 = tic;
        while toc(t0) < duration
            if sessionEnding, break; end
            processRx();
            retryCommitIfNeeded();
            pause(0.001);
        end

        safeWrite(tcpObj, uint8(OP_DONE), 'uint8', 'DONE');
        barrierLocalDone = true;

        tWait = tic;
        while ~barrierRemoteDone
            if sessionEnding, break; end
            processRx();
            retryCommitIfNeeded();
            if toc(tWait) > 5
                markTrialFallback('BLACK_DONE_TIMEOUT');
                break;
            end
            pause(0.001);
        end

        if ~isempty(ax) && isvalid(ax)
            showTargetCircles(-1);
        end
        if ~isempty(mouseDot) && isvalid(mouseDot)
            setMouseDotVisible(false);
        end
        drawnow;
        if isvalid(blk), delete(blk); end
        if ~sessionEnding && isvalid(fig)
            set(fig,'Color',origCol,'Units',origUnit,'WindowState',origWin);
            set(fig,'WindowButtonMotionFcn',@mouseMoved);
        end

    end

    function markTrialFallback(reason)
        if isempty(trialFallbackReason)
            trialFallbackReason = reason;
        elseif isempty(strfind(trialFallbackReason, reason)) %#ok<STREMP>
            trialFallbackReason = [trialFallbackReason ';' reason];
        end
        trialFallbackTriggered = 1;
    end

    function tStable = debounceTouch(rawLogic)
        if isnan(rawLogic)
            touchStable = 0;
            touchHiCnt  = 0;
            touchLoCnt  = 0;
            tStable     = 0;
            return;
        end

        pressed = (rawLogic == TOUCH_ACTIVE_LEVEL);
        if pressed
            touchHiCnt = touchHiCnt + 1;
            touchLoCnt = 0;
            if touchHiCnt >= TOUCH_FRAMES
                touchStable = 1;
            end
        else
            touchLoCnt = touchLoCnt + 1;
            touchHiCnt = 0;
            if touchLoCnt >= TOUCH_FRAMES
                touchStable = 0;
            end
        end
        tStable = touchStable;
    end

    function decideAndCommit()
        if trialFinalized || sessionEnding, return; end
        threshold = ttlDiffThreshold;

        if isnan(ttlFirstMove) || isnan(ttlEnd) || isnan(remoteTtlFirst) || isnan(remoteTtlEnd)
            sendCommit(trialIndex, STATUS_TTL_MISMATCH);
            finalizeTrial(STATUS_TTL_MISMATCH);
            return;
        end

        ttlStartDiff = round(abs(ttlFirstMove - remoteTtlFirst), 3);
        ttlEndDiff   = round(abs(ttlEnd       - remoteTtlEnd), 3);

        if ttlStartDiff <= threshold && ttlEndDiff <= threshold
            sendCommit(trialIndex, STATUS_SUCCESS);
            finalizeTrial(STATUS_SUCCESS);
        else
            sendCommit(trialIndex, STATUS_TTL_MISMATCH);
            finalizeTrial(STATUS_TTL_MISMATCH);
        end
    end

    function finalizeTrial(statusCode)
        if trialFinalized || sessionEnding, return; end
        trialFinalized = true;
        if statusCode == STATUS_SUCCESS
            successCount = successCount + 1;
        end
        updateRemainingTargetsAfterTrial(statusCode);
        stop(timerObj);
        totalTime = getTotalTime();
        cyclesCompleted = cyclesCompleted + 1;
        ensureTrialBlackScreenChoice();
        saveMousePathAndTrueCoordinates(mousePath, cyclesCompleted, totalTime, statusCode);
        resetMouseAndDotPositionToCenter(false);
        setMouseDotVisible(false);
        showTargetCircles(-1);
        showBlackPanelScreenSync(trialBlackScreenDuration);
        if successCount >= goalSuccesses
            sendStop();
            forceStop();
            return;
        end

        if cyclesCompleted < maxCycles
            resetTarget();
        else
            forceStop();
        end
    end


    function startTask()
        targetSequence   = selectedTargets;
        remainingPairs   = buildTrialPairs(selectedTargets, selectedModeIds);
        radii            = DEFAULT_RADIUS;
        circleDiameter   = targetCircleDiameter;
        circleDiameter2  = centerCircleDiameter;
        centerHoldDuration     = DEFAULT_CENTER_HOLD;
        targetHoldDuration     = DEFAULT_TARGET_HOLD;
        firstMovementThreshold = DEFAULT_FIRST_MOVE_THRESHOLD;
        maxCycles       = 999;
        cyclesCompleted = 0;
        rxbuf = uint8([]);
        awaitingAck4 = false;
        lastSend4Time = 0;
        ack4Tries = 0;
        syncEventTrial = -1;
        syncEventKind = 0;
        syncEventPartnerTarget = 0;
        syncEventLocalTarget = 0;
        syncEventModeId = 0;
        syncReadyForGo = false;
        syncGoAcked = false;
        syncPrepareLastSendTime = NaN;
        syncPrepareSendTries = 0;
        syncGoLastSendTime = NaN;
        syncGoSendTries = 0;
        syncGoEpochShared = NaN;
        centerSyncIssuedForTrial = 0;
        targetSyncIssuedForTrial = 0;
        localCenterHoldStartShared = NaN;
        remoteCenterHoldStartShared = NaN;
        commitAckForTrial = 0;
        commitLastSendTime = NaN;
        commitSendTries = 0;
        pendingCommitStatus = NaN;
        trialFallbackTriggered = 0;
        trialFallbackReason = '';
        angles = linspace(0, 2*pi, 9);
        angles = angles(1:end-1);
        targetCenters = zeros(8, 2);
        for i = 1:length(angles)
            targetCenters(i,1) = radii * cos(angles(i));
            targetCenters(i,2) = radii * sin(angles(i));
        end
        ttlFirstMove = NaN;
        ttlEnd       = NaN;
        remoteTtlFirst = NaN;
        remoteTtlEnd   = NaN;
        remoteCenterIdx = -1;
        lastCenterSent  = 0;
        centerexittime      = NaN;
        centerExitSource    = CENTER_EXIT_SOURCE_NONE;
        centerExitWriteTime = NaN;
        centerActivated     = false;
        centerEnterTime     = NaN;
        centerHoldStartTime = NaN;
        hoverEnterTime      = NaN;
        firstMove         = true;
        firstMoveStartPos = [NaN, NaN];
        targetActivated   = false;
        targetReachedOnce = false;
        localCenterDone   = false;
        remoteCenterDone  = false;
        mousePath = [];
        lastMoveTime  = NaN;
        resetPosition = [0,0];
        localSuccess   = false;
        remoteSuccess  = false;
        ttlStartDiff = NaN;
        ttlEndDiff   = NaN;
        trialIndex   = cyclesCompleted + 1;
        barrierRemoteReady = false;
        barrierRemoteDone  = false;
        barrierLocalReady  = false;
        barrierLocalDone   = false;
        touchStable = 0;
        touchHiCnt  = 0;
        touchLoCnt  = 0;
        centerOnTime = NaN;
        touchCenterStartTime = NaN;
        touchTargetStartTime = NaN;
        targetOnTime = NaN;
        trialBlackScreenChoiceIdx = 0;
        trialBlackScreenDuration = NaN;
        trialFinalized = false;
        trialFallbackTriggered = 0;
        trialFallbackReason = '';
        sessionEnding  = false;
        currentTarget = 0;
        currentPartnerTarget = 0;
        currentModeId = 0;
        pendingTargetTrial  = -1;
        pendingTarget       = 0;
        pendingPartnerTarget = 0;
        pendingModeId = 0;
        pendingOnsetEpochShared = NaN;
        pendingOnsetKind = 0;
        daqSession = daq("ni");
        addoutput(daqSession, "Dev4", "port0/line0:4", "Digital");
        addinput(daqSession,  "Dev4", "port1/line3",   "Digital");

        timerObj = timer('TimerFcn', @recordMousePos, ...
            'Period', 0.002, 'ExecutionMode', 'fixedRate');

        fig = figure('Color','black','Pointer','custom', ...
            'Units','normalized','Position',[0 0 1 1], ...
            'MenuBar','none','ToolBar','none','WindowState','fullscreen');

        ax = axes('Parent', fig, ...
            'Color','black','Units','normalized','Position',[0 0 1 1], ...
            'DataAspectRatio',[1 1 1]);
        axis off;
        hold on;

        set(fig, 'WindowButtonMotionFcn', @mouseMoved);
        showBlackPanelScreenSync(10);
        if sessionEnding, return; end
        drawCircles();
        setInvisibleCursor();
        resetMouseAndDotPositionToCenter();
        setMouseDotVisible(false);
        showTargetCircles(-1);
        trialStartEpochShared = NaN;
        start(timerObj);
        sendTTL(3);
    end

    function drawCircles()
        angles = linspace(0, 2*pi, 9);
        angles = angles(1:end-1);

        for i = 1:length(angles)
            x = radii * cos(angles(i));
            y = radii * sin(angles(i));
            rectangle('Position',[x - circleDiameter/2, y - circleDiameter/2, circleDiameter, circleDiameter], ...
                'Curvature',[1,1], 'EdgeColor','w','FaceColor','k', ...
                'LineStyle','--','LineWidth',3, 'UserData', i, ...
                'Tag','TARGET', 'Visible','off');
        end

        rectangle('Position',[-circleDiameter2/2, -circleDiameter2/2, circleDiameter2, circleDiameter2], ...
            'Curvature',[1,1], 'EdgeColor','w','FaceColor','w', ...
            'LineStyle','-', 'LineWidth',3, 'UserData',0, ...
            'Tag','CENTER', 'Visible','on');

        xlim([-0.5, 0.5]);
        ylim([-0.5, 0.5]);
    end

    function setInvisibleCursor()
        transparentCursor = NaN(16,16);
        hotspot = [8,8];
        set(fig, 'Pointer','custom', ...
            'PointerShapeCData',transparentCursor, ...
            'PointerShapeHotSpot',hotspot);
    end

    function resetMouseAndDotPositionToCenter(clearPath)
        if nargin < 1
            clearPath = true;
        end
        if isempty(mouseDot) || ~isvalid(mouseDot)
            mouseDot = plot(0,0,'r.','MarkerSize',100);
        end

        figPos = get(fig, 'Position');
        pixPos = getpixelposition(ax, true);
        axCenterX = figPos(1)*screenSize(3) + pixPos(1) + pixPos(3)/2;
        axCenterY = screenSize(4) - (figPos(2)*screenSize(4) + pixPos(2) + pixPos(4)/2);
        robot = java.awt.Robot;
        robot.mouseMove(round(axCenterX), round(axCenterY));
        pause(0.01);
        if clearPath
            mousePath = [];
        end
        resetPosition = [0, 0];
        set(mouseDot, 'XData',0,'YData',0);
    end

    function setMouseDotVisible(isVisible)
        if isempty(mouseDot) || ~isvalid(mouseDot), return; end
        if isVisible
            set(mouseDot, 'Visible', 'on');
        else
            set(mouseDot, 'Visible', 'off');
        end
    end

    function showTargetCircles(targetNum)
        centerObj  = findall(ax,'Type','rectangle','Tag','CENTER');
        circleObjs = findall(ax,'Type','rectangle','Tag','TARGET');

        if targetNum < 0
            if ~isempty(centerObj),  set(centerObj,  'Visible','off'); end
            if ~isempty(circleObjs), set(circleObjs, 'Visible','off'); end
            return;
        end

        if targetNum == 0
            if ~isempty(centerObj),  set(centerObj,  'Visible','on');  end
            if ~isempty(circleObjs), set(circleObjs, 'Visible','off'); end
            return;
        end

        if ~isempty(centerObj), set(centerObj,'Visible','off'); end
        for i = 1:numel(circleObjs)
            idx = get(circleObjs(i),'UserData');
            if isempty(idx) || ~isscalar(idx), continue; end
            if idx == targetNum
                set(circleObjs(i), 'Visible','on', ...
                    'FaceColor','w','EdgeColor','w', ...
                    'LineStyle','-','LineWidth',3);
            else
                set(circleObjs(i), 'Visible','off');
            end
        end
    end

    function mouseMoved(~,~)
        if sessionEnding, return; end
        if isempty(timerObj) || strcmp(timerObj.Running,'off'), return; end
        if isempty(fig) || ~isvalid(fig), return; end
        if isempty(ax) || ~isvalid(ax), return; end

        C = get(ax, 'CurrentPoint');
        x = C(1,1);
        y = C(1,2);

        x = max(-0.5, min(0.5, x));
        y = max(-0.5, min(0.5, y));

        if isempty(mouseDot) || ~isvalid(mouseDot)
            mouseDot = plot(x, y, 'r.', 'MarkerSize', 100);
        else
            set(mouseDot, 'XData', x, 'YData', y);
        end
        if ~centerActivated && ~targetActivated
            setMouseDotVisible(false);
        end
    end
    function recordMousePos(~, ~)
        if sessionEnding, return; end
        if strcmp(timerObj.Running, 'off'), return; end
        if isempty(mouseDot) || ~isvalid(mouseDot), return; end
        x = get(mouseDot, 'XData');
        y = get(mouseDot, 'YData');
        t = nowTrial();
        if isnan(t) || t < 0
            t = 0;
        end
        t = round(t, 3);
        mousePath = [mousePath; x, y, t];

        processRx();
        retryCenterDoneIfNeeded();
        maybeDriveOnsetSync();
        maybeActivateScheduledOnset(t);
        if trialFinalized || sessionEnding, return; end

        needTouch = (centerActivated && inCenter(x,y)) || (targetActivated && inTarget(x,y,currentTarget));
        if needTouch
            scanData = read(daqSession, 1, "OutputFormat", "Matrix");
            rawTouch = scanData(1);
            touchVal = debounceTouch(rawTouch);
        else
            touchVal = debounceTouch(NaN);
        end
        checkFirstMove();
        logic(x, y, touchVal);
        maybeActivateScheduledOnset(t);
        if ~trialFinalized
            checkTimeout();
        end
    end

    function clearPendingOnset()
        pendingTargetTrial  = -1;
        pendingTarget       = 0;
        pendingPartnerTarget = 0;
        pendingModeId = 0;
        pendingOnsetEpochShared = NaN;
        pendingOnsetKind = 0;
    end

    function clearSyncEvent()
        syncEventTrial = -1;
        syncEventKind = 0;
        syncEventPartnerTarget = 0;
        syncEventLocalTarget = 0;
        syncEventModeId = 0;
        syncReadyForGo = false;
        syncGoAcked = false;
        syncPrepareLastSendTime = NaN;
        syncPrepareSendTries = 0;
        syncGoLastSendTime = NaN;
        syncGoSendTries = 0;
        syncGoEpochShared = NaN;
    end

    function scheduleOnsetActivation(eventKind, localTgt, partnerTgt, modeId, goTime, trialNum)
        if trialFinalized || sessionEnding, return; end
        if trialNum ~= trialIndex, return; end
        pendingTargetTrial  = trialNum;
        pendingTarget       = double(localTgt);
        pendingPartnerTarget = double(partnerTgt);
        pendingModeId = double(modeId);
        pendingOnsetEpochShared = goTime;
        pendingOnsetKind = double(eventKind);
    end

    function maybeActivateScheduledOnset(~)
        if trialFinalized || sessionEnding, return; end
        if isnan(pendingOnsetEpochShared), return; end
        if pendingTargetTrial ~= trialIndex
            clearPendingOnset();
            return;
        end
        if nowShared() >= pendingOnsetEpochShared
            if pendingOnsetKind == EVENT_TARGET_ON && centerActivated && ~localCenterDone
                return;
            end
            localTgt = pendingTarget;
            partnerTgt = pendingPartnerTarget;
            modeId = pendingModeId;
            eventKind = pendingOnsetKind;
            clearPendingOnset();
            switch eventKind
                case EVENT_CENTER_ON
                    activateCenterSynced();
                case EVENT_TARGET_ON
                    activateTargetSynced(localTgt, partnerTgt, modeId);
            end
            if syncGoAcked && syncEventTrial == trialIndex && syncEventKind == eventKind && pendingOnsetKind == 0
                clearSyncEvent();
            end
        end
    end

    function retryCenterDoneIfNeeded()
        if trialFinalized || sessionEnding, return; end
        if ~awaitingAck4, return; end
        if lastCenterSent ~= trialIndex, return; end
        if ack4Tries >= CENTER_ACK_MAX_TRIES, return; end
        nowRel = nowMonotonic();
        if (nowRel - lastSend4Time) < CENTER_ACK_RETRY_INTERVAL, return; end
        payload = [uint8(OP_CENTER_DONE), typecast(uint16(trialIndex),'uint8')];
        safeWrite(tcpObj, payload, 'uint8', 'CENTER_RETRY');
        lastSend4Time = nowRel;
        ack4Tries = ack4Tries + 1;
    end

    function retryCommitIfNeeded()
        if sessionEnding, return; end
        if isnan(pendingCommitStatus), return; end
        if commitAckForTrial == trialIndex, return; end
        if commitSendTries >= COMMIT_MAX_TRIES, return; end
        nowRel = nowMonotonic();
        if ~isnan(commitLastSendTime) && (nowRel - commitLastSendTime) < COMMIT_RETRY_INTERVAL
            return;
        end
        sendCommitPacket(trialIndex, pendingCommitStatus, 'COMMIT_RETRY');
    end

    function beginSyncEvent(eventKind, partnerTgt, localTgt, modeId)
        clearSyncEvent();
        syncEventTrial = trialIndex;
        syncEventKind = double(eventKind);
        syncEventPartnerTarget = double(partnerTgt);
        syncEventLocalTarget = double(localTgt);
        syncEventModeId = double(modeId);
    end

    function sendPrepareOnsetPacket()
        if syncEventTrial ~= trialIndex || syncEventKind == 0, return; end
        payload = [ ...
            uint8(OP_PREPARE_ONSET), ...
            typecast(uint16(syncEventTrial),'uint8'), ...
            uint8(syncEventKind), ...
            uint8(syncEventPartnerTarget), ...
            uint8(syncEventLocalTarget), ...
            uint8(syncEventModeId) ...
            ];
        safeWrite(tcpObj, payload, 'uint8', 'PREPARE_ONSET');
        syncPrepareLastSendTime = nowMonotonic();
        syncPrepareSendTries = syncPrepareSendTries + 1;
    end

    function sendGoCuePacket()
        if syncEventTrial ~= trialIndex || syncEventKind == 0 || isnan(syncGoEpochShared), return; end
        payload = [ ...
            uint8(OP_GO_CUE), ...
            typecast(uint16(syncEventTrial),'uint8'), ...
            uint8(syncEventKind), ...
            typecast(syncGoEpochShared,'uint8') ...
            ];
        safeWrite(tcpObj, payload, 'uint8', 'GO_CUE');
        syncGoLastSendTime = nowMonotonic();
        syncGoSendTries = syncGoSendTries + 1;
    end

    function maybeDriveOnsetSync()
        if trialFinalized || sessionEnding, return; end

        if syncEventTrial == trialIndex && syncEventKind ~= 0
            if syncGoAcked && pendingOnsetKind == 0
                clearSyncEvent();
                return;
            end

            if ~syncReadyForGo
                if syncPrepareSendTries < SYNC_PREPARE_MAX_TRIES
                    nowRel = nowMonotonic();
                    if isnan(syncPrepareLastSendTime) || (nowRel - syncPrepareLastSendTime) >= SYNC_PREPARE_RETRY_INTERVAL
                        sendPrepareOnsetPacket();
                    end
                end
                return;
            end

            if syncEventKind == EVENT_TARGET_ON && isnan(syncGoEpochShared)
                if isnan(localCenterHoldStartShared) || isnan(remoteCenterHoldStartShared)
                    return;
                end
            end

            if isnan(syncGoEpochShared)
                if syncEventKind == EVENT_CENTER_ON
                    syncGoEpochShared = nowShared() + CENTER_SYNC_GO_LEAD;
                else
                    % Target onset is anchored to the later center-hold start,
                    % so the prepare handshake no longer adds post-hold delay.
                    plannedTargetOn = max(localCenterHoldStartShared, remoteCenterHoldStartShared) + centerHoldDuration;
                    minFutureOn = nowShared() + TARGET_SYNC_GO_LEAD;
                    syncGoEpochShared = max(plannedTargetOn, minFutureOn);
                end
                if syncEventKind == EVENT_CENTER_ON
                    trialStartEpochShared = syncGoEpochShared;
                end
                scheduleOnsetActivation(syncEventKind, syncEventLocalTarget, syncEventPartnerTarget, syncEventModeId, syncGoEpochShared, trialIndex);
            end

            if ~syncGoAcked && syncGoSendTries < SYNC_GO_MAX_TRIES
                nowRel = nowMonotonic();
                if isnan(syncGoLastSendTime) || (nowRel - syncGoLastSendTime) >= SYNC_GO_RETRY_INTERVAL
                    sendGoCuePacket();
                end
            end
            return;
        end

        if ~centerActivated && ~targetActivated && centerSyncIssuedForTrial ~= trialIndex
            centerSyncIssuedForTrial = trialIndex;
            beginSyncEvent(EVENT_CENTER_ON, 0, 0, 0);
            return;
        end

        if targetSyncIssuedForTrial == trialIndex, return; end
        if ~centerActivated || targetActivated, return; end
        if isempty(remainingPairs)
            remainingPairs = buildTrialPairs(selectedTargets, selectedModeIds);
        end
        if isempty(remainingPairs)
            return;
        end
        targetSyncIssuedForTrial = trialIndex;
        beginSyncEvent(EVENT_TARGET_ON, remainingPairs(1,1), remainingPairs(1,2), remainingPairs(1,3));
    end

    function activateCenterSynced()
        localSuccess  = false;
        remoteSuccess = false;
        clearPendingOnset();
        localCenterDone = false;
        remoteCenterDone = false;
        currentTarget = 0;
        currentPartnerTarget = 0;
        currentModeId = 0;
        targetActivated = false;
        centerActivated = true;
        centerEnterTime = NaN;
        centerHoldStartTime = NaN;
        centerexittime = NaN;
        centerExitSource = CENTER_EXIT_SOURCE_NONE;
        centerExitWriteTime = NaN;
        hoverEnterTime = NaN;
        targetReachedOnce = false;
        touchCenterStartTime = NaN;
        touchTargetStartTime = NaN;
        showTargetCircles(0);
        centerOnTime = round(nowShared(), 3);
        setMouseDotVisible(true);
        firstMove = true;
        firstMoveStartPos = [NaN, NaN];
    end

    function activateTargetSynced(localTgt, partnerTgt, modeId)
        localSuccess  = false;
        remoteSuccess = false;
        clearPendingOnset();
        if ~ensureCenterHoldCompletedForTargetOn()
            return;
        end
        currentTarget   = double(localTgt);
        currentPartnerTarget = double(partnerTgt);
        currentModeId = double(modeId);
        targetActivated = true;
        centerActivated = false;
        hoverEnterTime    = NaN;
        targetReachedOnce = false;
        touchTargetStartTime = NaN;
        showTargetCircles(currentTarget);
        targetOnTime = round(nowShared(), 3);
        setMouseDotVisible(true);
        firstMove = true;
        if isempty(mouseDot) || ~isvalid(mouseDot)
            firstMoveStartPos = [0, 0];
        else
            firstMoveStartPos = [get(mouseDot,'XData'), get(mouseDot,'YData')];
        end
    end

    function completed = ensureCenterHoldCompletedForTargetOn()
        completed = localCenterDone;
        if completed
            return;
        end
        if isnan(centerHoldStartTime)
            return;
        end
        plannedExitTime = round(centerHoldStartTime + centerHoldDuration, 3);
        tNow = round(nowTrial(), 3);
        if tNow + 0.002 < plannedExitTime
            return;
        end
        if isnan(centerexittime)
            markCenterExit(plannedExitTime, CENTER_EXIT_SOURCE_TARGET_ON_FILL);
        end
        localCenterDone = true;
        lastCenterSent = trialIndex;
        payload = [uint8(OP_CENTER_DONE), typecast(uint16(trialIndex),'uint8')];
        safeWrite(tcpObj, payload, 'uint8', 'CENTER_AT_TARGET_ON');
        awaitingAck4 = true;
        lastSend4Time = nowMonotonic();
        ack4Tries = 0;
        completed = true;
    end

    function markCenterExit(exitTime, sourceCode)
        centerexittime = round(exitTime, 3);
        centerExitSource = sourceCode;
        centerExitWriteTime = round(nowShared(), 3);
    end

    function markCenterHoldStart(tNow)
        centerHoldStartTime = tNow;
        localCenterHoldStartShared = round(trialStartEpochShared + tNow, 3);
        maybeDriveOnsetSync();
    end

    function logic(x, y, touchVal)
        if trialFinalized || sessionEnding, return; end
        tNow = round(nowTrial(), 3);
        if centerActivated
            if inCenter(x, y)
                if isnan(centerEnterTime)
                    centerEnterTime = tNow;
                end

                if touchVal == 1 && isnan(touchCenterStartTime)
                    touchCenterStartTime = tNow;
                end

                if isnan(centerHoldStartTime)
                    if touchVal == 1
                        markCenterHoldStart(tNow);
                    end
                else
                    if touchVal == 0
                        sendCommit(trialIndex, STATUS_R_CENTER_REL);
                        finalizeTrial(STATUS_R_CENTER_REL);
                        return;
                    end

                    if ~localCenterDone && (tNow >= centerHoldStartTime + centerHoldDuration)
                        markCenterExit(tNow, CENTER_EXIT_SOURCE_LOGIC);
                        localCenterDone  = true;
                        lastCenterSent   = trialIndex;
                        payload = [uint8(OP_CENTER_DONE), typecast(uint16(trialIndex),'uint8')];
                        safeWrite(tcpObj, payload, 'uint8', 'CENTER');
                        awaitingAck4  = true;
                        lastSend4Time = nowMonotonic();
                        ack4Tries     = 0;
                        maybeDriveOnsetSync();
                    elseif localCenterDone
                        maybeDriveOnsetSync();
                    end
                end
            else
                if ~isnan(centerEnterTime) || localCenterDone
                    sendCommit(trialIndex, STATUS_R_CENTER_EXIT);
                    finalizeTrial(STATUS_R_CENTER_EXIT);
                    return;
                end
            end
            return;
        end

        if targetActivated
            if ~localSuccess
                if inTarget(x, y, currentTarget)
                    if touchVal == 1 && isnan(touchTargetStartTime)
                        touchTargetStartTime = tNow;
                    end

                    if isnan(hoverEnterTime)
                        if touchVal == 1
                            hoverEnterTime    = tNow;
                            targetReachedOnce = false;
                        end
                    else
                        if touchVal == 0
                            sendCommit(trialIndex, STATUS_R_TARGET_REL);
                            finalizeTrial(STATUS_R_TARGET_REL);
                            return;
                        end

                        if ~targetReachedOnce && (tNow >= hoverEnterTime + targetHoldDuration)
                            targetReachedOnce = true;

                            sendTTL(2);

                            localSuccess = true;

                            if remoteSuccess
                                decideAndCommit();
                            end
                            return;
                        end
                    end
                else
                    if ~isnan(hoverEnterTime)
                        sendCommit(trialIndex, STATUS_R_TARGET_EXIT);
                        finalizeTrial(STATUS_R_TARGET_EXIT);
                        return;
                    else
                        hoverEnterTime    = NaN;
                        targetReachedOnce = false;
                    end
                end
            else
                if ~inTarget(x, y, currentTarget)
                    sendCommit(trialIndex, STATUS_R_TARGET_EXIT);
                    finalizeTrial(STATUS_R_TARGET_EXIT);
                    return;
                end
                if touchVal == 0
                    sendCommit(trialIndex, STATUS_R_TARGET_REL);
                    finalizeTrial(STATUS_R_TARGET_REL);
                    return;
                end
            end
        end
    end

    function tf = inCenter(x, y)
        d  = sqrt(x^2 + y^2);
        tf = (d < 0.5*circleDiameter2);
    end

    function tf = inTarget(x, y, targetNum)
        if targetNum == 0
            tf = false;
            return;
        end
        centerX = targetCenters(targetNum,1);
        centerY = targetCenters(targetNum,2);
        d       = sqrt((x - centerX)^2 + (y - centerY)^2);
        tf      = (d < 0.5*circleDiameter);
    end

    function checkFirstMove()
        persistent aboveThresholdCount
        if isempty(aboveThresholdCount), aboveThresholdCount = 0; end
        consecutiveFrames = 10;
        if firstMove && ~centerActivated && targetActivated
            if any(isnan(firstMoveStartPos))
                if isempty(mouseDot) || ~isvalid(mouseDot)
                    firstMoveStartPos = [0, 0];
                else
                    firstMoveStartPos = [get(mouseDot,'XData'), get(mouseDot,'YData')];
                end
            end
            pos = [get(mouseDot,'XData'), get(mouseDot,'YData')];
            distFromTargetOnset = norm(pos - firstMoveStartPos);

            if distFromTargetOnset > firstMovementThreshold
                aboveThresholdCount = aboveThresholdCount + 1;
                if aboveThresholdCount >= consecutiveFrames
                    lastMoveTime = round(nowShared(), 3);
                    sendTTL(1);
                    firstMove    = false;
                end
            else
                aboveThresholdCount = 0;
            end
        else
            aboveThresholdCount = 0;
        end
    end

    function checkTimeout()
        if nowTrial() > 8 && ~trialFinalized
            sendCommit(trialIndex, STATUS_R_TIMEOUT);
            finalizeTrial(STATUS_R_TIMEOUT);
        end
    end

    function sendTTL(signalType)
        if isempty(daqSession) || ~isvalid(daqSession), return; end
        nowRel = round(nowShared(), 3);
        switch signalType
            case 1
                ttlFirstMove = nowRel;
                write(daqSession,[1 1 0 1 0]); pause(0.01); write(daqSession,[1 1 0 0 0]);
            case 2
                ttlEnd = nowRel;
                write(daqSession,[1 1 0 0 1]); pause(0.01); write(daqSession,[1 1 0 0 0]);
            case 3
                write(daqSession,[1 0 1 0 0]); pause(0.01); write(daqSession,[1 1 0 0 0]);
        end
    end

    function tt = getTotalTime()
        % Duration should reflect the actual trial finalization time,
        % not the timestamp of the last sampled trajectory point.
        tt = nowTrial();
        if isnan(tt) || tt < 0
            tt = 0;
        end
        tt = round(tt, 3);
    end

    function setTrialBlackScreenChoice(choiceIdx)
        choiceIdx = max(1, min(numel(blackScreenDurations), round(double(choiceIdx))));
        trialBlackScreenChoiceIdx = choiceIdx;
        trialBlackScreenDuration = blackScreenDurations(choiceIdx);
    end

    function chooseRandomTrialBlackScreen()
        setTrialBlackScreenChoice(randi(numel(blackScreenDurations)));
    end

    function ensureTrialBlackScreenChoice()
        if trialBlackScreenChoiceIdx <= 0 || isnan(trialBlackScreenDuration)
            chooseRandomTrialBlackScreen();
        end
    end

    function resetTarget()
        trialIndex = cyclesCompleted + 1;
        clearSyncEvent();
        centerSyncIssuedForTrial = 0;
        targetSyncIssuedForTrial = 0;
        commitAckForTrial = 0;
        commitLastSendTime = NaN;
        commitSendTries = 0;
        pendingCommitStatus = NaN;
        trialFallbackTriggered = 0;
        trialFallbackReason = '';
        mousePath      = [];
        ttlFirstMove   = NaN;
        ttlEnd         = NaN;
        remoteTtlFirst = NaN;
        remoteTtlEnd   = NaN;
        centerexittime = NaN;
        centerExitSource = CENTER_EXIT_SOURCE_NONE;
        centerExitWriteTime = NaN;
        ttlStartDiff = NaN;
        ttlEndDiff   = NaN;
        lastMoveTime = NaN;
        centerOnTime = NaN;
        targetOnTime = NaN;
        localCenterHoldStartShared = NaN;
        remoteCenterHoldStartShared = NaN;
        centerEnterTime     = NaN;
        centerHoldStartTime = NaN;
        hoverEnterTime      = NaN;
        touchCenterStartTime = NaN;
        touchTargetStartTime = NaN;
        lastCenterSent  = 0;
        targetActivated = false;
        centerActivated = false;
        firstMove       = true;
        firstMoveStartPos = [NaN, NaN];
        localCenterDone  = false;
        remoteCenterDone = false;
        awaitingAck4  = false;
        lastSend4Time = 0;
        ack4Tries     = 0;
        touchStable = 0;
        touchHiCnt  = 0;
        touchLoCnt  = 0;
        trialBlackScreenChoiceIdx = 0;
        trialBlackScreenDuration = NaN;
        currentTarget = 0;
        currentPartnerTarget = 0;
        currentModeId = 0;
        clearPendingOnset();
        trialFinalized = false;
        localSuccess  = false;
        remoteSuccess = false;
        resetMouseAndDotPositionToCenter();
        setMouseDotVisible(false);
        showTargetCircles(-1);
        trialStartEpochShared = NaN;
        start(timerObj);
        sendTTL(3);
    end

    function tRel = sharedTimeToTrialTime(sharedTime)
        if isnan(sharedTime) || isnan(trialStartEpochShared)
            tRel = NaN;
        else
            tRel = round(sharedTime - trialStartEpochShared, 3);
        end
    end

    function val = summaryCellToDouble(cellValue)
        if isnumeric(cellValue)
            if isempty(cellValue)
                val = NaN;
            else
                val = double(cellValue);
            end
        elseif islogical(cellValue)
            val = double(cellValue);
        elseif isstring(cellValue) || ischar(cellValue)
            val = str2double(cellValue);
        else
            val = NaN;
        end
        if isempty(val) || ~isscalar(val) || ~isfinite(val)
            val = NaN;
        end
    end

    function cellValue = sanitizeSummaryCell(cellValue)
        if ismissing(cellValue)
            cellValue = NaN;
        elseif isstring(cellValue)
            cellValue = char(cellValue);
        end
    end

    function colData = deriveRelativeSummaryColumn(data, existingHeader, sharedHeaderName)
        colData = repmat({NaN}, size(data,1), 1);
        sharedIdx = find(strcmp(existingHeader, sharedHeaderName), 1, 'first');
        centerIdx = find(strcmp(existingHeader, 'CenterOnSharedTime'), 1, 'first');
        if isempty(sharedIdx) || isempty(centerIdx)
            return;
        end
        for row = 1:size(data,1)
            sharedVal = summaryCellToDouble(data{row, sharedIdx});
            centerVal = summaryCellToDouble(data{row, centerIdx});
            if isfinite(sharedVal) && isfinite(centerVal)
                colData{row} = round(sharedVal - centerVal, 3);
            end
        end
    end

    function colData = deriveSummarySchemaColumn(data, existingHeader, columnName)
        colData = repmat({NaN}, size(data,1), 1);
        directIdx = find(strcmp(existingHeader, columnName), 1, 'first');
        if ~isempty(directIdx)
            colData = data(:, directIdx);
            for row = 1:size(colData,1)
                colData{row} = sanitizeSummaryCell(colData{row});
            end
            return;
        end

        switch columnName
            case 'CenterOnTime'
                colData = deriveRelativeSummaryColumn(data, existingHeader, 'CenterOnSharedTime');
            case 'FirstMoveTime'
                colData = deriveRelativeSummaryColumn(data, existingHeader, 'FirstMoveSharedTime');
            case 'TargetOnTime'
                colData = deriveRelativeSummaryColumn(data, existingHeader, 'TargetOnSharedTime');
            case 'TTL_FirstMove'
                colData = deriveRelativeSummaryColumn(data, existingHeader, 'TTL_FirstMoveShared');
            case 'TTL_End'
                colData = deriveRelativeSummaryColumn(data, existingHeader, 'TTL_EndShared');
            case 'CenterExitSource'
                colData = repmat({CENTER_EXIT_SOURCE_NONE}, size(data,1), 1);
            case 'CenterExitWriteSharedTime'
                colData = repmat({NaN}, size(data,1), 1);
            case 'FallbackTriggered'
                colData = repmat({0}, size(data,1), 1);
            case 'FallbackReason'
                colData = repmat({''}, size(data,1), 1);
        end
    end

    function ensureSummarySchema(summaryFile, desiredHeader)
        if ~isfile(summaryFile)
            writecell(desiredHeader, summaryFile);
            return;
        end

        existing = readcell(summaryFile);
        if isempty(existing)
            writecell(desiredHeader, summaryFile);
            return;
        end

        existingHeader = existing(1,:);
        if size(existing,2) >= numel(desiredHeader) && isequal(existingHeader(1:numel(desiredHeader)), desiredHeader)
            return;
        end

        data = existing(2:end,:);
        if size(data,2) < numel(existingHeader)
            data(:, size(data,2)+1:numel(existingHeader)) = {[]};
        end

        upgraded = cell(size(data,1), numel(desiredHeader));
        for col = 1:numel(desiredHeader)
            upgraded(:, col) = deriveSummarySchemaColumn(data, existingHeader, desiredHeader{col});
        end
        writecell([desiredHeader; upgraded], summaryFile);
    end

    function recordData = saveMousePathAndTrueCoordinates(pathData, cyc, totalTime, status)
        if isempty(pathData)
            recordData = [];
            return;
        end
        if targetActivated
            targetDir = currentTarget;
            partnerDir = currentPartnerTarget;
            modeId = currentModeId;
        else
            targetDir = 0;
            partnerDir = 0;
            modeId = 0;
        end
        saveTag = sessionSaveTag();
        folderName = fullfile(pwd, sprintf('S1_R_%s', saveTag));
        if ~exist(folderName,'dir'), mkdir(folderName); end
        if totalTime > pathData(end,3)
            % Keep the saved trace aligned with the summary duration.
            pathData(end+1,:) = [pathData(end,1), pathData(end,2), totalTime];
        end
        pathData = round(pathData, 3);
        traceFile = fullfile(folderName, ['right' num2str(cyc) '.xlsx']);
        writematrix(pathData, traceFile);
        centerOnTrialTime = sharedTimeToTrialTime(centerOnTime);
        firstMoveTrialTime = sharedTimeToTrialTime(lastMoveTime);
        targetOnTrialTime = sharedTimeToTrialTime(targetOnTime);
        ttlFirstMoveTrial = sharedTimeToTrialTime(ttlFirstMove);
        ttlEndTrial = sharedTimeToTrialTime(ttlEnd);
        trialData = [cyc, targetDir, partnerDir, modeId, totalTime, firstMoveTrialTime, targetOnTrialTime, status, ...
            ttlFirstMoveTrial, ttlEndTrial, ttlStartDiff, ttlEndDiff, centerexittime, ...
            touchCenterStartTime, touchTargetStartTime, hoverEnterTime, trialBlackScreenDuration, ...
            centerOnTrialTime, centerOnTime, lastMoveTime, targetOnTime, ttlFirstMove, ttlEnd];
        trialData = round(trialData, 3);
        trialRow = [num2cell(trialData), {centerExitSource, centerExitWriteTime, double(trialFallbackTriggered ~= 0), trialFallbackReason}];

        summaryFile = fullfile(folderName,'Summary_Data_R.xlsx');
        header = {'Trial','LocalTarget','PartnerTarget','ModeId','Dur','FirstMoveTime','TargetOnTime','Status', ...
            'TTL_FirstMove','TTL_End','TTL_StartDiff','TTL_EndDiff','Centerexittime', ...
            'TouchCenterStart','TouchTargetStart','MoveEnd','BlackScreenDur', ...
            'CenterOnTime','CenterOnSharedTime','FirstMoveSharedTime','TargetOnSharedTime','TTL_FirstMoveShared','TTL_EndShared', ...
            'CenterExitSource','CenterExitWriteSharedTime','FallbackTriggered','FallbackReason'};
        ensureSummarySchema(summaryFile, header);

        writecell(trialRow, summaryFile,'WriteMode','append');
        recordData = trialData;
    end
end
