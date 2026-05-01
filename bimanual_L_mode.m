function bimanual_L_mode(goalSuccessesInput)
global targetCenters targetSequence circleDiameter circleDiameter2 radii;
global centerHoldDuration centerEnterTime hoverEnterTime targetHoldDuration centerActivated centerHoldStartTime;
global firstMove firstMovementThreshold resetPosition targetReachedOnce;
global targetActivated currentTarget rxbuf awaitingAck4 lastSend4Time ack4Tries;
global cyclesCompleted maxCycles mousePath timerObj;
global lastMoveTime remainingPairs;
global mouseDot ax fig screenSize remoteCenterIdx lastCenterSent barrierRemoteReady barrierRemoteDone barrierLocalReady barrierLocalDone;
global tcpObj isServer ttlStartDiff ttlEndDiff;
global daqSession centerexittime localCenterDone remoteCenterDone trialIndex;
global localSuccess remoteSuccess failInProgress ttlFirstMove ttlEnd remoteTtlFirst remoteTtlEnd;
global goalSuccesses successCount;

TOUCH_ACTIVE_LEVEL = 1;
TOUCH_FRAMES       = 10;
DEFAULT_TARGET_SEQUENCE = [1, 3, 5, 7];
DEFAULT_BLACK_SCREEN_DURATIONS = [4, 4.5, 5];
DEFAULT_TTL_DIFF_THRESHOLD = 0.3;
DEFAULT_TARGET_DIAMETER    = 0.12;
DEFAULT_CENTER_DIAMETER    = 0.12;
DEFAULT_RADIUS             = 0.24;
DEFAULT_CENTER_HOLD        = 0.8;
DEFAULT_TARGET_HOLD        = 0.8;
DEFAULT_FIRST_MOVE_THRESHOLD = 0.0184;
COMMIT_RETRY_INTERVAL   = 0.008;
COMMIT_MAX_TRIES        = 10;
COMMIT_HARD_TIMEOUT     = COMMIT_RETRY_INTERVAL * COMMIT_MAX_TRIES;
CENTER_ACK_RETRY_INTERVAL = 0.008;
CENTER_ACK_MAX_TRIES      = 300;
TARGET_DONE_RETRY_INTERVAL = 0.008;
TARGET_DONE_MAX_TRIES      = 160;
STATUS_SUCCESS        = 1;
STATUS_L_CENTER_EXIT  = 2;
STATUS_L_CENTER_REL   = 3;
STATUS_L_TARGET_EXIT  = 4;
STATUS_L_TARGET_REL   = 5;
STATUS_L_TIMEOUT      = 6;
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
clockOffsetToShared = NaN;
trialStartEpochShared = NaN;
sharedClockReady = false;
lastClockSyncSeq = -1;
targetDoneAckForTrial = 0;
targetDoneLastSendTime = NaN;
targetDoneSendTries = 0;
targetDonePending = false;
centerOnTime = NaN;
currentPartnerTarget = 0;
currentModeId = 0;
pendingPartnerTarget = 0;
pendingModeId = 0;
pendingOnsetKind = 0;
preparedOnsetTrial = -1;
preparedOnsetKind = 0;
preparedOnsetLocalTarget = 0;
preparedOnsetPartnerTarget = 0;
preparedOnsetModeId = 0;
goAckTrial = -1;
goAckEventKind = 0;
remainingPairs = zeros(0,3);
selectedTargets = DEFAULT_TARGET_SEQUENCE;
selectedModeIds = MODE_INPHASE;
errorPolicyId = ERROR_REQUEUE_TO_END;
blackScreenDurations = DEFAULT_BLACK_SCREEN_DURATIONS;
targetCircleDiameter = DEFAULT_TARGET_DIAMETER;
centerCircleDiameter = DEFAULT_CENTER_DIAMETER;
sessionConfigReceived = false;
receivedSessionConfig = [];

if nargin < 1
    goalSuccesses = 100;
else
    goalSuccesses = goalSuccessesInput;
end
goalSuccessesDefault = goalSuccesses;
successCount = 0;

isServer = false;
tcpObj = initNetwork(isServer);
screenSize = get(groot, 'ScreenSize');
trialFinalized  = false;
awaitingCommit  = false;
sessionEnding   = false;
touchCenterStartTime = NaN;
touchTargetStartTime = NaN;
targetOnTime = NaN;
centerOnTime = NaN;
localCenterHoldStartShared = NaN;
centerHoldStartAckForTrial = 0;
centerHoldStartLastSendTime = NaN;
centerHoldStartSendTries = 0;
centerHoldStartPending = false;
trialBlackScreenDuration = NaN;
currentTarget = 0;
pendingTargetTrial  = -1;
pendingTarget       = 0;
pendingOnsetEpochShared = NaN;
pendingOnsetKind = 0;
awaitingCommitSince = NaN;
awaitingCommitStartTime = NaN;
pendingLocalFailStatus = NaN;
trialFallbackTriggered = 0;
trialFallbackReason = '';
centerExitSource = CENTER_EXIT_SOURCE_NONE;
centerExitWriteTime = NaN;

runConfig = waitForSessionConfig();
if isempty(runConfig)
    return;
end
applyRunConfig(runConfig);
if ~waitForSharedClockSync()
    return;
end
startTask();

    function tcpObj = initNetwork(serverFlag)
        if serverFlag
            tcpObj = [];
        else
            serverIP   = "192.168.0.10";
            serverPort = 30000;
            tcpObj = tcpclient(serverIP, serverPort, "Timeout", 30);
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

    function [hasPacket, op, payload] = extractNextPacket()
        hasPacket = false;
        op = uint8(0);
        payload = uint8([]);
        if numel(rxbuf) < 1
            return;
        end

        op = rxbuf(1);
        if op == OP_SESSION_CONFIG
            if numel(rxbuf) < 3
                return;
            end
            need = double(typecast(uint8(rxbuf(2:3)), 'uint16'));
            if numel(rxbuf) < 3 + need
                return;
            end
            payload = rxbuf(4 : 3 + need);
            rxbuf = rxbuf(4 + need : end);
        else
            need = payloadLen(op);
            if numel(rxbuf) < 1 + need
                return;
            end
            payload = rxbuf(2 : 1 + need);
            rxbuf = rxbuf(2 + need : end);
        end
        hasPacket = true;
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
        blackScreenDurations = cfg.blackScreenDurations;
        targetCircleDiameter = cfg.targetCircleDiameter;
        centerCircleDiameter = cfg.centerCircleDiameter;
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

    function cfg = decodeSessionConfig(payload)
        jsonText = native2unicode(payload(:).', 'UTF-8');
        cfg = normalizeRunConfig(jsondecode(jsonText), goalSuccessesDefault);
    end

    function cfg = waitForSessionConfig()
        cfg = [];
        disp('Connected to right side. Waiting for shared session parameters...');
        while true
            if sessionEnding
                return;
            end
            pumpNetwork();
            while true
                [hasPacket, op, payload] = extractNextPacket();
                if ~hasPacket
                    break;
                end

                switch op
                    case OP_SESSION_CONFIG
                        if ~sessionConfigReceived
                            receivedSessionConfig = decodeSessionConfig(payload);
                            sessionConfigReceived = true;
                            applyRunConfig(receivedSessionConfig);
                        end
                        safeWrite(tcpObj, uint8(OP_SESSION_CONFIG_ACK), 'uint8', 'SESSION_CONFIG_ACK');
                        cfg = receivedSessionConfig;
                        return;

                    case OP_STOP
                        sessionEnding = true;
                        return;

                    otherwise
                        % Ignore all trial-time packets until configuration arrives.
                end
            end
            pause(0.01);
        end
    end

    function ok = waitForSharedClockSync()
        ok = false;
        while ~sharedClockReady
            if sessionEnding
                return;
            end
            processRx();
            pause(0.001);
        end
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

    function processRx()
        pumpNetwork();
        while true
            if sessionEnding, return; end
            [hasPacket, op, payload] = extractNextPacket();
            if ~hasPacket
                break;
            end

            switch op
                case OP_READY
                    barrierRemoteReady = true;

                case OP_DONE
                    barrierRemoteDone  = true;

                case OP_STOP
                    forceStop();
                    return;

                case OP_SESSION_CONFIG
                    if ~sessionConfigReceived
                        receivedSessionConfig = decodeSessionConfig(payload);
                        sessionConfigReceived = true;
                    end
                    safeWrite(tcpObj, uint8(OP_SESSION_CONFIG_ACK), 'uint8', 'SESSION_CONFIG_ACK');

                case OP_SESSION_CONFIG_ACK
                    % Left side only acknowledges session-configuration packets.

                case OP_CENTER_DONE
                    rTrial = double(typecast(uint8(payload(1:2)), 'uint16'));
                    safeWrite(tcpObj, [uint8(OP_CENTER_ACK), typecast(uint16(rTrial),'uint8')], 'uint8', 'ACK');
                    if rTrial > remoteCenterIdx
                        remoteCenterIdx = rTrial;
                    end

                case OP_CENTER_ACK
                    ackIdx = double(typecast(uint8(payload(1:2)), 'uint16'));
                    if ackIdx == trialIndex
                        awaitingAck4 = false;
                    end

                case OP_CENTER_HOLD_START_ACK
                    ackIdx = double(typecast(uint8(payload(1:2)), 'uint16'));
                    if ackIdx == trialIndex
                        centerHoldStartAckForTrial = ackIdx;
                        centerHoldStartPending = false;
                    end

                case OP_CLOCK_SYNC_REQ
                    rSeq = double(typecast(uint8(payload(1:2)), 'uint16'));
                    masterSend = double(typecast(uint8(payload(3:10)), 'double'));
                    remoteMono = nowMonotonic();
                    reply = [ ...
                        uint8(OP_CLOCK_SYNC_REPLY), ...
                        typecast(uint16(rSeq), 'uint8'), ...
                        typecast(masterSend, 'uint8'), ...
                        typecast(remoteMono, 'uint8') ...
                        ];
                    safeWrite(tcpObj, reply, 'uint8', 'CLOCK_SYNC_REPLY');

                case OP_CLOCK_SYNC_SET
                    rSeq = double(typecast(uint8(payload(1:2)), 'uint16'));
                    if rSeq ~= lastClockSyncSeq
                        clockOffsetToShared = double(typecast(uint8(payload(3:10)), 'double'));
                        sharedClockReady = true;
                        lastClockSyncSeq = rSeq;
                    end
                    safeWrite(tcpObj, [uint8(OP_CLOCK_SYNC_ACK), typecast(uint16(rSeq), 'uint8')], 'uint8', 'CLOCK_SYNC_ACK');

                case OP_PREPARE_ONSET
                    rTrial = double(typecast(uint8(payload(1:2)), 'uint16'));
                    eventKind = double(payload(3));
                    leftTgt  = double(payload(4));
                    rightTgt = double(payload(5));
                    modeId   = double(payload(6));
                    if rTrial == trialIndex && ~trialFinalized
                        preparedOnsetTrial = rTrial;
                        preparedOnsetKind = eventKind;
                        preparedOnsetLocalTarget = leftTgt;
                        preparedOnsetPartnerTarget = rightTgt;
                        preparedOnsetModeId = modeId;
                    end
                    safeWrite(tcpObj, [uint8(OP_READY_FOR_GO), typecast(uint16(rTrial),'uint8'), uint8(eventKind)], 'uint8', 'READY_FOR_GO');

                case OP_GO_CUE
                    rTrial = double(typecast(uint8(payload(1:2)), 'uint16'));
                    eventKind = double(payload(3));
                    goEpochShared = double(typecast(uint8(payload(4:11)), 'double'));
                    safeWrite(tcpObj, [uint8(OP_GO_ACK), typecast(uint16(rTrial),'uint8'), uint8(eventKind)], 'uint8', 'GO_ACK');
                    if rTrial == goAckTrial && eventKind == goAckEventKind
                        continue;
                    end
                    goAckTrial = rTrial;
                    goAckEventKind = eventKind;
                    if rTrial ~= trialIndex || trialFinalized
                        continue;
                    end
                    if preparedOnsetTrial ~= rTrial || preparedOnsetKind ~= eventKind
                        continue;
                    end
                    if pendingTargetTrial == rTrial && pendingOnsetKind == eventKind && ~isnan(pendingOnsetEpochShared)
                        continue;
                    end
                    if eventKind == EVENT_CENTER_ON
                        trialStartEpochShared = goEpochShared;
                    end
                    scheduleOnsetActivation(eventKind, preparedOnsetLocalTarget, preparedOnsetPartnerTarget, preparedOnsetModeId, goEpochShared, rTrial);

                case OP_TARGET_DONE_ACK
                    ackTrial = double(typecast(uint8(payload(1:2)), 'uint16'));
                    if ackTrial == trialIndex
                        targetDoneAckForTrial = ackTrial;
                        targetDonePending = false;
                    end

                case OP_COMMIT
                    rTrial = double(typecast(uint8(payload(1:2)), 'uint16'));
                    st     = double(payload(3));
                    blackScreenChoiceIdx = double(payload(4));
                    safeWrite(tcpObj, [uint8(OP_COMMIT_ACK), typecast(uint16(rTrial),'uint8')], 'uint8', 'COMMIT_ACK');
                    if rTrial == trialIndex && ~trialFinalized
                        awaitingCommit = false;
                        awaitingCommitSince = NaN;
                        awaitingCommitStartTime = NaN;
                        pendingLocalFailStatus = NaN;
                        setTrialBlackScreenChoice(blackScreenChoiceIdx);
                        finalizeTrial(st);
                    end

                case OP_COMMIT_ACK
                    % Left side only acknowledges COMMIT packets.

                case OP_READY_FOR_GO
                    % Left side only sends READY_FOR_GO packets.

                case OP_GO_ACK
                    % Left side only sends GO_ACK packets.

                case OP_CLOCK_SYNC_REPLY
                    % Left side only sends CLOCK_SYNC_REPLY packets.

                case OP_CLOCK_SYNC_ACK
                    % Left side only sends CLOCK_SYNC_ACK packets.

                otherwise
            end
        end
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

        key = [currentTarget, currentPartnerTarget, currentModeId];
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
                    % Keep the current pair available immediately.
                case ERROR_RESHUFFLE
                    remainingPairs = remainingPairs(randperm(size(remainingPairs,1)), :);
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
            pause(0.001);
        end

        safeWrite(tcpObj, uint8(OP_DONE), 'uint8', 'DONE');
        barrierLocalDone = true;

        tWait = tic;
        while ~barrierRemoteDone
            if sessionEnding, break; end
            processRx();
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

    function sendFail(statusCode)
        if sessionEnding || trialFinalized, return; end
        targetDonePending = false;
        payload = [uint8(OP_FAIL), typecast(uint16(trialIndex),'uint8'), uint8(statusCode)];
        safeWrite(tcpObj, payload, 'uint8', 'FAIL');
        if ~awaitingCommit || isnan(awaitingCommitStartTime)
            awaitingCommitStartTime = nowMonotonic();
        end
        awaitingCommit = true;
        awaitingCommitSince = nowMonotonic();
        pendingLocalFailStatus = statusCode;
    end

    function finalizeTrial(statusCode)
        if trialFinalized || sessionEnding, return; end
        trialFinalized = true;
        awaitingCommit = false;
        awaitingCommitSince = NaN;
        awaitingCommitStartTime = NaN;
        pendingLocalFailStatus = NaN;
        targetDonePending = false;
        if statusCode == STATUS_SUCCESS
            successCount = successCount + 1;
            sendTTL(4);
        end
        updateRemainingTargetsAfterTrial(statusCode);
        stop(timerObj);
        totalTime = getTotalTime();
        cyclesCompleted = cyclesCompleted + 1;
        if isnan(trialBlackScreenDuration)
            chooseRandomTrialBlackScreen();
        end
        saveMousePathAndTrueCoordinates(mousePath, cyclesCompleted, totalTime, statusCode);
        resetMouseAndDotPositionToCenter(false);
        setMouseDotVisible(false);
        showTargetCircles(-1);
        showBlackPanelScreenSync(trialBlackScreenDuration);
        % Session length is owned by the right/master side. The left side
        % keeps following until it receives OP_STOP, otherwise GUI rounding
        % on the right could make the two sides stop at different counts.
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
        targetDoneAckForTrial = 0;
        targetDoneLastSendTime = NaN;
        targetDoneSendTries = 0;
        targetDonePending = false;
        localCenterHoldStartShared = NaN;
        centerHoldStartAckForTrial = 0;
        centerHoldStartLastSendTime = NaN;
        centerHoldStartSendTries = 0;
        centerHoldStartPending = false;
        preparedOnsetTrial = -1;
        preparedOnsetKind = 0;
        preparedOnsetLocalTarget = 0;
        preparedOnsetPartnerTarget = 0;
        preparedOnsetModeId = 0;
        goAckTrial = -1;
        goAckEventKind = 0;
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
        failInProgress = false;
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
        trialBlackScreenDuration = NaN;
        trialFinalized = false;
        awaitingCommit = false;
        awaitingCommitSince = NaN;
        awaitingCommitStartTime = NaN;
        pendingLocalFailStatus = NaN;
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
        addoutput(daqSession, "Dev3", "port0/line0:4", "Digital");
        addinput(daqSession,  "Dev3", "port1/line3",   "Digital");

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
        retryCenterHoldStartIfNeeded();
        retryCenterDoneIfNeeded();
        retryTargetDoneIfNeeded();
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

    function sendCenterHoldStartPacket(tag)
        if isnan(localCenterHoldStartShared), return; end
        payload = [ ...
            uint8(OP_CENTER_HOLD_START), ...
            typecast(uint16(trialIndex),'uint8'), ...
            typecast(localCenterHoldStartShared, 'uint8') ...
            ];
        safeWrite(tcpObj, payload, 'uint8', tag);
        centerHoldStartLastSendTime = nowMonotonic();
        centerHoldStartSendTries = centerHoldStartSendTries + 1;
    end

    function retryCenterHoldStartIfNeeded()
        if trialFinalized || sessionEnding, return; end
        if ~centerHoldStartPending, return; end
        if centerHoldStartAckForTrial == trialIndex, return; end
        if centerHoldStartSendTries >= CENTER_ACK_MAX_TRIES, return; end
        nowRel = nowMonotonic();
        if ~isnan(centerHoldStartLastSendTime) && (nowRel - centerHoldStartLastSendTime) < CENTER_ACK_RETRY_INTERVAL
            return;
        end
        sendCenterHoldStartPacket('CENTER_HOLD_START_RETRY');
    end

    function sendTargetDonePacket(tag)
        payload = [ ...
            uint8(OP_TARGET_DONE), ...
            typecast(uint16(trialIndex),'uint8'), ...
            typecast([ttlFirstMove, ttlEnd], 'uint8') ...
            ];
        safeWrite(tcpObj, payload, 'uint8', tag);
        targetDoneLastSendTime = nowMonotonic();
        targetDoneSendTries = targetDoneSendTries + 1;
    end

    function retryTargetDoneIfNeeded()
        if trialFinalized || sessionEnding, return; end
        if ~targetDonePending, return; end
        if targetDoneAckForTrial == trialIndex, return; end
        if targetDoneSendTries >= TARGET_DONE_MAX_TRIES, return; end
        nowRel = nowMonotonic();
        if ~isnan(targetDoneLastSendTime) && (nowRel - targetDoneLastSendTime) < TARGET_DONE_RETRY_INTERVAL
            return;
        end
        sendTargetDonePacket('TARGET_DONE_RETRY');
    end

    function clearPendingOnset()
        pendingTargetTrial  = -1;
        pendingTarget       = 0;
        pendingPartnerTarget = 0;
        pendingModeId = 0;
        pendingOnsetEpochShared = NaN;
        pendingOnsetKind = 0;
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
        end
    end

    function activateCenterSynced()
        localSuccess  = false;
        remoteSuccess = false;
        clearPendingOnset();
        localCenterDone  = false;
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
        hoverEnterTime      = NaN;
        targetReachedOnce   = false;
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
        centerHoldStartAckForTrial = 0;
        centerHoldStartLastSendTime = NaN;
        centerHoldStartSendTries = 0;
        centerHoldStartPending = true;
        sendCenterHoldStartPacket('CENTER_HOLD_START');
    end

    function logic(x, y, touchVal)
        if trialFinalized || sessionEnding, return; end
        if awaitingCommit, return; end
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
                        sendFail(STATUS_L_CENTER_REL);
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
                    end
                end
            else
                if ~isnan(centerEnterTime) || localCenterDone
                    sendFail(STATUS_L_CENTER_EXIT);
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
                            sendFail(STATUS_L_TARGET_REL);
                            return;
                        end

                        if ~targetReachedOnce && (tNow >= hoverEnterTime + targetHoldDuration)
                            targetReachedOnce = true;

                            sendTTL(2);
                            targetDoneAckForTrial = 0;
                            targetDoneLastSendTime = NaN;
                            targetDoneSendTries = 0;
                            targetDonePending = true;
                            sendTargetDonePacket('TARGET_DONE');

                            localSuccess = true;
                            return;
                        end
                    end
                else
                    if ~isnan(hoverEnterTime)
                        sendFail(STATUS_L_TARGET_EXIT);
                        return;
                    else
                        hoverEnterTime    = NaN;
                        targetReachedOnce = false;
                    end
                end
            else
                if ~inTarget(x, y, currentTarget)
                    sendFail(STATUS_L_TARGET_EXIT);
                    return;
                end
                if touchVal == 0
                    sendFail(STATUS_L_TARGET_REL);
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
        if awaitingCommit
            nowRel = nowMonotonic();
            if isnan(awaitingCommitSince)
                awaitingCommitSince = nowRel;
            end
            if isnan(awaitingCommitStartTime)
                awaitingCommitStartTime = nowRel;
            end

            if (nowRel - awaitingCommitSince) > COMMIT_RETRY_INTERVAL
                st = pendingLocalFailStatus;
                if isnan(st)
                    st = STATUS_L_TIMEOUT;
                end
                payload = [uint8(OP_FAIL), typecast(uint16(trialIndex),'uint8'), uint8(st)];
                safeWrite(tcpObj, payload, 'uint8', 'FAIL_RETRY');
                awaitingCommitSince = nowRel;
            end

            if (nowRel - awaitingCommitStartTime) > COMMIT_HARD_TIMEOUT
                markTrialFallback('COMMIT_HARD_TIMEOUT');
                fallbackStatus = pendingLocalFailStatus;
                if isnan(fallbackStatus)
                    fallbackStatus = STATUS_L_TIMEOUT;
                end
                finalizeTrial(fallbackStatus);
            end
            return;
        end

        if nowTrial() > 8
            sendFail(STATUS_L_TIMEOUT);
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
            case 4
                write(daqSession,[0 1 1 0 0]); pause(0.01); write(daqSession,[1 1 0 0 0]);
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
        trialBlackScreenDuration = blackScreenDurations(choiceIdx);
    end

    function chooseRandomTrialBlackScreen()
        setTrialBlackScreenChoice(randi(numel(blackScreenDurations)));
    end

    function resetTarget()
        trialIndex = cyclesCompleted + 1;
        targetDoneAckForTrial = 0;
        targetDoneLastSendTime = NaN;
        targetDoneSendTries = 0;
        targetDonePending = false;
        preparedOnsetTrial = -1;
        preparedOnsetKind = 0;
        preparedOnsetLocalTarget = 0;
        preparedOnsetPartnerTarget = 0;
        preparedOnsetModeId = 0;
        goAckTrial = -1;
        goAckEventKind = 0;
        mousePath      = [];
        ttlFirstMove   = NaN;
        ttlEnd         = NaN;
        remoteTtlFirst = NaN;
        remoteTtlEnd   = NaN;
        ttlStartDiff = NaN;
        ttlEndDiff   = NaN;
        lastMoveTime = NaN;
        centerOnTime = NaN;
        targetOnTime = NaN;
        localCenterHoldStartShared = NaN;
        centerHoldStartAckForTrial = 0;
        centerHoldStartLastSendTime = NaN;
        centerHoldStartSendTries = 0;
        centerHoldStartPending = false;
        centerEnterTime     = NaN;
        centerHoldStartTime = NaN;
        hoverEnterTime      = NaN;
        centerexittime      = NaN;
        centerExitSource = CENTER_EXIT_SOURCE_NONE;
        centerExitWriteTime = NaN;
        touchCenterStartTime = NaN;
        touchTargetStartTime = NaN;
        targetActivated = false;
        centerActivated = false;
        firstMove       = true;
        firstMoveStartPos = [NaN, NaN];
        localCenterDone  = false;
        remoteCenterDone = false;
        lastCenterSent  = 0;
        awaitingAck4  = false;
        lastSend4Time = 0;
        ack4Tries     = 0;
        touchStable = 0;
        touchHiCnt  = 0;
        touchLoCnt  = 0;
        trialBlackScreenDuration = NaN;
        currentTarget = 0;
        currentPartnerTarget = 0;
        currentModeId = 0;
        clearPendingOnset();
        trialFinalized = false;
        awaitingCommit = false;
        awaitingCommitSince = NaN;
        awaitingCommitStartTime = NaN;
        pendingLocalFailStatus = NaN;
        trialFallbackTriggered = 0;
        trialFallbackReason = '';
        localSuccess = false;
        resetMouseAndDotPositionToCenter();
        setMouseDotVisible(false);
        showTargetCircles(-1);
        trialStartEpochShared = NaN;
        start(timerObj);
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
        folderName = fullfile(pwd, sprintf('S1_L_%s', saveTag));
        if ~exist(folderName,'dir'), mkdir(folderName); end
        if totalTime > pathData(end,3)
            % Keep the saved trace aligned with the summary duration.
            pathData(end+1,:) = [pathData(end,1), pathData(end,2), totalTime];
        end
        pathData = round(pathData, 3);

        traceFile = fullfile(folderName, ['left' num2str(cyc) '.xlsx']);
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

        summaryFile = fullfile(folderName,'Summary_Data_L.xlsx');
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
