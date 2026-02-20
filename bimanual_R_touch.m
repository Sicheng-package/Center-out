function bimanual_R_touch(goalSuccessesInput)
global targetCenters targetSequence circleDiameter circleDiameter2 radii;
global centerHoldDuration centerEnterTime hoverEnterTime targetHoldDuration centerActivated centerHoldStartTime;
global firstMove firstMovementThreshold resetPosition targetReachedOnce;
global targetActivated currentTarget remoteCenterIdx lastCenterSent;
global cyclesCompleted maxCycles mousePath timerObj rxbuf awaitingAck4 lastSend4Time ack4Tries;
global cycleStartTime lastMoveTime remainingTargets;
global mouseDot ax fig screenSize barrierRemoteReady barrierRemoteDone barrierLocalReady barrierLocalDone;
global tcpObj isServer ttlStartDiff ttlEndDiff;
global daqSession centerexittime localCenterDone remoteCenterDone trialIndex;
global localSuccess remoteSuccess failInProgress ttlFirstMove ttlEnd remoteTtlFirst remoteTtlEnd;
global goalSuccesses successCount;

TOUCH_ACTIVE_LEVEL = 1;
TOUCH_FRAMES       = 5;
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
OP_TARGET_ON   = 6;
OP_COMMIT      = 7;
OP_READY       = 10;
OP_DONE        = 11;
OP_STOP        = 20;
touchStable = 0;
touchHiCnt  = 0;
touchLoCnt  = 0;
targetSyncSentForTrial = 0;
targetSyncRecvForTrial = 0;

if nargin < 1
    goalSuccesses = 100;
else
    goalSuccesses = goalSuccessesInput;
end
successCount = 0;
isServer = true;
tcpObj   = initNetwork(isServer);
screenSize = get(groot, 'ScreenSize');
trialFinalized  = false;
awaitingCommit  = false;
sessionEnding   = false;
inBlackScreen   = false;
touchCenterStartTime = NaN;
touchTargetStartTime = NaN;
currentTarget = 0;
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

    function L = payloadLen(op_)
        switch op_
            case OP_TARGET_DONE, L = 18;
            case OP_FAIL,        L = 3;
            case OP_CENTER_DONE, L = 2;
            case OP_CENTER_ACK,  L = 2;
            case OP_TARGET_ON,   L = 3;
            case OP_COMMIT,      L = 3;
            case OP_READY,       L = 0;
            case OP_DONE,        L = 0;
            case OP_STOP,        L = 0;
            otherwise,           L = 0;
        end
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

    function sendCommit(trialNum, statusCode)
        payload = [uint8(OP_COMMIT), typecast(uint16(trialNum),'uint8'), uint8(statusCode)];
        safeWrite(tcpObj, payload, 'uint8', 'COMMIT');
    end

    function sendStop()
        safeWrite(tcpObj, uint8(OP_STOP), 'uint8', 'STOP');
    end

    function updateRemainingTargetsAfterTrial(statusCode)
        if currentTarget <= 0 || isempty(remainingTargets)
            return;
        end

        idx = find(remainingTargets == currentTarget, 1, 'first');
        if isempty(idx)
            return;
        end

        if statusCode == STATUS_SUCCESS
            remainingTargets(idx) = [];
        else
            tgt = remainingTargets(idx);
            remainingTargets(idx) = [];
            remainingTargets(end+1) = tgt;
        end
    end

    function processRx()
        pumpNetwork();
        while true
            if sessionEnding, return; end
            if numel(rxbuf) < 1, break; end
            op = rxbuf(1);
            need = payloadLen(op);
            if numel(rxbuf) < 1 + need
                break;
            end
            payload = rxbuf(2 : 1 + need);
            rxbuf   = rxbuf(2 + need : end);

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
                    maybeSendTargetSync();

                case OP_CENTER_ACK
                    ackIdx = double(typecast(uint8(payload(1:2)), 'uint16'));
                    if ackIdx == trialIndex
                        awaitingAck4 = false;
                    end

                case OP_TARGET_DONE
                    rTrial = double(typecast(uint8(payload(1:2)), 'uint16'));
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
        inBlackScreen = true;
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
                break;
            end
            pause(0.001);
        end

        if sessionEnding
            inBlackScreen = false;
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
                break;
            end
            pause(0.001);
        end

        if isvalid(blk), delete(blk); end
        if ~sessionEnding && isvalid(fig)
            set(fig,'Color',origCol,'Units',origUnit,'WindowState',origWin);
            set(fig,'WindowButtonMotionFcn',@mouseMoved);
        end

        inBlackScreen = false;
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
        threshold = 0.5;

        if isnan(ttlFirstMove) || isnan(ttlEnd) || isnan(remoteTtlFirst) || isnan(remoteTtlEnd)
            sendCommit(trialIndex, STATUS_TTL_MISMATCH);
            finalizeTrial(STATUS_TTL_MISMATCH);
            return;
        end

        ttlStartDiff = abs(ttlFirstMove - remoteTtlFirst);
        ttlEndDiff   = abs(ttlEnd       - remoteTtlEnd);

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
        saveMousePathAndTrueCoordinates(mousePath, cyclesCompleted, totalTime, statusCode);
        showBlackPanelScreenSync(3);
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
        targetSequence   = [7,3,1,5];
        remainingTargets = targetSequence;
        radii            = 0.24;
        circleDiameter   = 0.12;
        circleDiameter2  = 0.12;
        centerHoldDuration     = 0.8;
        targetHoldDuration     = 0.8;
        firstMovementThreshold = 0.06;
        maxCycles       = 999;
        cyclesCompleted = 0;
        rxbuf = uint8([]);
        awaitingAck4 = false;
        lastSend4Time = 0;
        ack4Tries = 0;
        targetSyncSentForTrial = 0;
        targetSyncRecvForTrial = 0;
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
        centerActivated     = true;
        centerEnterTime     = NaN;
        centerHoldStartTime = NaN;
        hoverEnterTime      = NaN;
        firstMove         = true;
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
        touchCenterStartTime = NaN;
        touchTargetStartTime = NaN;
        trialFinalized = false;
        awaitingCommit = false;
        sessionEnding  = false;
        inBlackScreen  = false;
        currentTarget = 0;
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
        showTargetCircles(0);
        cycleStartTime = tic;
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

    function resetMouseAndDotPositionToCenter()
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
        mousePath     = [];
        resetPosition = [0, 0];
        set(mouseDot, 'XData',0,'YData',0);
    end

    function showTargetCircles(targetNum)
        centerObj  = findall(ax,'Type','rectangle','Tag','CENTER');
        circleObjs = findall(ax,'Type','rectangle','Tag','TARGET');

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
    end

    function recordMousePos(~, ~)
        if sessionEnding, return; end
        if strcmp(timerObj.Running, 'off'), return; end
        if isempty(mouseDot) || ~isvalid(mouseDot), return; end
        x = get(mouseDot, 'XData');
        y = get(mouseDot, 'YData');
        t = toc(cycleStartTime);
        mousePath = [mousePath; x, y, t];
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
        if ~trialFinalized
            checkTimeout();
        end
        processRx();
    end

    function maybeSendTargetSync()
        if trialFinalized || sessionEnding, return; end
        if targetActivated, return; end
        if ~localCenterDone, return; end
        if remoteCenterIdx < trialIndex, return; end
        if targetSyncSentForTrial == trialIndex, return; end

        if isempty(remainingTargets)
            remainingTargets = targetSequence;
        end

        tgt = remainingTargets(1);
        payload = [uint8(OP_TARGET_ON), typecast(uint16(trialIndex),'uint8'), uint8(tgt)];
        safeWrite(tcpObj, payload, 'uint8', 'TARGET_ON');

        targetSyncSentForTrial = trialIndex;
        activateTargetSynced(tgt);
    end

    function activateTargetSynced(tgt)
        localSuccess  = false;
        remoteSuccess = false;
        currentTarget   = double(tgt);
        targetActivated = true;
        centerActivated = false;
        hoverEnterTime    = NaN;
        targetReachedOnce = false;
        touchTargetStartTime = NaN;
        showTargetCircles(currentTarget);
        firstMove = true;
    end

    function logic(x, y, touchVal)
        if trialFinalized || sessionEnding, return; end
        tNow = toc(cycleStartTime);
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
                        centerHoldStartTime = tNow;
                    end
                else
                    if touchVal == 0
                        sendCommit(trialIndex, STATUS_R_CENTER_REL);
                        finalizeTrial(STATUS_R_CENTER_REL);
                        return;
                    end

                    if ~localCenterDone && (tNow >= centerHoldStartTime + centerHoldDuration)
                        centerexittime   = tNow;
                        localCenterDone  = true;
                        lastCenterSent   = trialIndex;
                        payload = [uint8(OP_CENTER_DONE), typecast(uint16(trialIndex),'uint8')];
                        safeWrite(tcpObj, payload, 'uint8', 'CENTER');
                        awaitingAck4  = true;
                        lastSend4Time = toc(cycleStartTime);
                        ack4Tries     = 0;
                        maybeSendTargetSync();
                    elseif localCenterDone
                        maybeSendTargetSync();
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
        consecutiveFrames = 5;
        if firstMove && ~centerActivated && targetActivated
            pos = [get(mouseDot,'XData'), get(mouseDot,'YData')];
            distFromCenter = norm(pos - [0,0]);

            if distFromCenter > firstMovementThreshold
                aboveThresholdCount = aboveThresholdCount + 1;
                if aboveThresholdCount >= consecutiveFrames
                    lastMoveTime = toc(cycleStartTime);
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
        if toc(cycleStartTime) > 8 && ~trialFinalized
            sendCommit(trialIndex, STATUS_R_TIMEOUT);
            finalizeTrial(STATUS_R_TIMEOUT);
        end
    end

    function sendTTL(signalType)
        if isempty(daqSession) || ~isvalid(daqSession), return; end
        nowRel = toc(cycleStartTime);
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
        if ~isempty(mousePath) && size(mousePath,2) >= 3
            tt = mousePath(end,3);
        else
            tt = toc(cycleStartTime);
        end
    end

    function resetTarget()
        trialIndex = cyclesCompleted + 1;
        targetSyncSentForTrial = 0;
        targetSyncRecvForTrial = 0;
        mousePath      = [];
        ttlFirstMove   = NaN;
        ttlEnd         = NaN;
        remoteTtlFirst = NaN;
        remoteTtlEnd   = NaN;
        centerexittime = NaN;
        ttlStartDiff = NaN;
        ttlEndDiff   = NaN;
        lastMoveTime = NaN;
        centerEnterTime     = NaN;
        centerHoldStartTime = NaN;
        hoverEnterTime      = NaN;
        touchCenterStartTime = NaN;
        touchTargetStartTime = NaN;
        lastCenterSent  = 0;
        targetActivated = false;
        centerActivated = true;
        firstMove       = true;
        localCenterDone  = false;
        remoteCenterDone = false;
        awaitingAck4  = false;
        lastSend4Time = 0;
        ack4Tries     = 0;
        touchStable = 0;
        touchHiCnt  = 0;
        touchLoCnt  = 0;
        currentTarget = 0;
        trialFinalized = false;
        awaitingCommit = false;
        localSuccess  = false;
        remoteSuccess = false;
        resetMouseAndDotPositionToCenter();
        showTargetCircles(0);
        cycleStartTime = tic;
        start(timerObj);
        sendTTL(3);
    end

    function recordData = saveMousePathAndTrueCoordinates(pathData, cyc, totalTime, status)
        if isempty(pathData)
            recordData = [];
            return;
        end
        if targetActivated
            targetDir = currentTarget;
        else
            targetDir = 0;
        end
        folderName = fullfile(pwd,'S1_R');
        if ~exist(folderName,'dir'), mkdir(folderName); end
        traceFile = fullfile(folderName, ['right' num2str(cyc) '.xlsx']);
        writematrix(pathData, traceFile);
        trialData = [cyc, targetDir, totalTime, lastMoveTime, status, ...
            ttlFirstMove, ttlEnd, ttlStartDiff, ttlEndDiff, centerexittime, ...
            touchCenterStartTime, touchTargetStartTime];

        summaryFile = fullfile(folderName,'Summary_Data_R1.xlsx');
        if ~isfile(summaryFile)
            header = {'Trial','Target','Dur','FirstMoveTime','Status', ...
                'TTL_FirstMove','TTL_End','TTL_StartDiff','TTL_EndDiff','Centerexittime', ...
                'TouchCenterStart','TouchTargetStart'};
            writecell(header, summaryFile);
        end

        writematrix(trialData, summaryFile,'WriteMode','append');
        recordData = trialData;
    end
end
