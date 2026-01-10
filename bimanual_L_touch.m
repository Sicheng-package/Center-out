function bimanual_L_touch(goalSuccessesInput)
global targetCenters targetSequence circleDiameter circleDiameter2 radii;
global centerHoldDuration centerEnterTime hoverEnterTime targetHoldDuration centerActivated centerHoldStartTime;
global firstMove firstMovementThreshold resetPosition targetReachedOnce;
global targetActivated currentTarget rxbuf awaitingAck4 lastSend4Time ack4Tries;
global cyclesCompleted maxCycles mousePath timerObj;
global cycleStartTime lastMoveTime remainingTargets;
global mouseDot ax fig screenSize remoteCenterIdx lastCenterSent barrierRemoteReady barrierRemoteDone barrierLocalReady barrierLocalDone;
global tcpObj isServer ttlStartDiff ttlEndDiff;
global daqSession centerexittime localCenterDone remoteCenterDone trialIndex;
global localSuccess remoteSuccess failInProgress ttlFirstMove ttlEnd remoteTtlFirst remoteTtlEnd;
global goalSuccesses successCount;

TOUCH_ACTIVE_LEVEL = 1;
TOUCH_FRAMES       = 5;
touchStable = 0;
touchHiCnt  = 0;
touchLoCnt  = 0;

targetSyncSentForTrial = 0;
targetSyncRecvForTrial = 0;

if nargin < 1
    goalSuccesses = 120;
else
    goalSuccesses = goalSuccessesInput;
end
successCount = 0;

isServer = false;
tcpObj = initNetwork(isServer);

screenSize = get(groot, 'ScreenSize');
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

    function sendSignal(obj, val)
        write(obj, uint8(val), "uint8");
    end

    function showBlackPanelScreenSync(duration)
        barrierRemoteReady = false;
        barrierRemoteDone  = false;
        barrierLocalReady  = false;
        barrierLocalDone   = false;
        safeWrite(tcpObj, uint8(10), 'uint8', 'READY');
        barrierLocalReady = true;

        tWait = tic;
        while ~barrierRemoteReady
            pumpBarrierBytes();
            if toc(tWait) > 5
                warning('Barrier: peer READY timeout.');
                break;
            end
            pause(0.001);
        end
        origCol = get(fig,'Color'); origUnit = get(fig,'Units');
        origWin = get(fig,'WindowState'); set(fig,'WindowState','fullscreen');
        blk = uipanel('Parent',fig,'Units','normalized','Position',[0 0 1 1], ...
            'BackgroundColor','black','BorderType','none'); drawnow;
        set(fig,'WindowButtonMotionFcn','');

        t0 = tic;
        while toc(t0) < duration
            pumpBarrierBytes();
            pause(0.001);
        end

        safeWrite(tcpObj, uint8(11), 'uint8', 'DONE');
        barrierLocalDone = true;
        tWait = tic;
        while ~barrierRemoteDone
            pumpBarrierBytes();
            if toc(tWait) > 5
                warning('Barrier: peer DONE timeout.');
                break;
            end
            pause(0.001);
        end

        delete(blk);
        set(fig,'Color',origCol,'Units',origUnit,'WindowState',origWin);
        set(fig,'WindowButtonMotionFcn',@mouseMoved);
    end

    function pumpBarrierBytes()
        n = tcpObj.NumBytesAvailable;
        if n <= 0, return; end
        bytes = read(tcpObj, n, 'uint8');
        other = uint8([]);
        for k = 1:numel(bytes)
            b = bytes(k);
            if b == 10
                barrierRemoteReady = true;
            elseif b == 11
                barrierRemoteDone  = true;
            else
                other(end+1,1) = b;
            end
        end
        if ~isempty(other)
            rxbuf = [rxbuf; other];
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

    function doBothSuccess()
        if ~isempty(remainingTargets)
            remainingTargets(1) = [];
        end
        sendTTL(4);
        stop(timerObj);
        totalTime = getTotalTime();
        cyclesCompleted = cyclesCompleted + 1;
        saveMousePathAndTrueCoordinates(mousePath, cyclesCompleted, totalTime, 1);
        successCount = successCount + 1;
        showBlackPanelScreenSync(3);

        if successCount >= goalSuccesses
            stop(timerObj);
            delete(timerObj);
            close(fig);
            return;
        end

        if cyclesCompleted < maxCycles
            resetTarget();
        else
            stop(timerObj);
            delete(timerObj);
            close(fig);
        end
    end

    function doBothFail()
        stop(timerObj);

        totalTime = getTotalTime();
        cyclesCompleted = cyclesCompleted + 1;
        saveMousePathAndTrueCoordinates(mousePath, cyclesCompleted, totalTime, 2);

        showBlackPanelScreenSync(3);

        if successCount >= goalSuccesses
            stop(timerObj);
            delete(timerObj);
            close(fig);
            return;
        end

        if cyclesCompleted < maxCycles
            resetTarget();
        else
            stop(timerObj);
            delete(timerObj);
            close(fig);
        end
    end

    function checkRemoteSignal()
        n = tcpObj.NumBytesAvailable;
        if n > 0
            rxbuf = [rxbuf; read(tcpObj, n, 'uint8')];
        end

        while true
            if numel(rxbuf) < 1, break; end
            op = rxbuf(1);
            need = payloadLen(op);
            if numel(rxbuf) < 1 + need
                break;
            end
            payload = rxbuf(2 : 1 + need);
            rxbuf   = rxbuf(2 + need : end);

            switch op
                case 2
                    rTrial = double(typecast(uint8(payload(1:2)), 'uint16'));
                    if rTrial ~= trialIndex
                        continue;
                    end
                    times = typecast(uint8(payload(3:end)), 'double');
                    remoteTtlFirst = times(1);
                    remoteTtlEnd   = times(2);
                    remoteSuccess  = true;
                    if localSuccess, compareTtlAndProceed(); end

                case 3
                    remoteSuccess = false;
                    if ~failInProgress
                        failInProgress = true;
                        doBothFail();
                    end

                case 4
                    rTrial = double(typecast(uint8(payload(1:2)), 'uint16'));
                    write(tcpObj, [uint8(5), typecast(uint16(rTrial),'uint8')], 'uint8');
                    if rTrial > remoteCenterIdx
                        remoteCenterIdx = rTrial;
                    end

                case 5
                    ackIdx = double(typecast(uint8(payload(1:2)), 'uint16'));
                    if ackIdx == trialIndex
                        awaitingAck4 = false;
                    end

                case 6
                    rTrial = double(typecast(uint8(payload(1:2)), 'uint16'));
                    tgt    = double(payload(3));
                    if rTrial == trialIndex
                        if targetSyncRecvForTrial ~= rTrial
                            targetSyncRecvForTrial = rTrial;
                            activateTargetSynced(tgt);
                        end
                    end

                case 10
                    barrierRemoteReady = true;

                case 11
                    barrierRemoteDone  = true;

                otherwise
            end
        end

        function L = payloadLen(op_)
            switch op_
                case 2,  L = 18;
                case 3,  L = 0;
                case 4,  L = 2;
                case 5,  L = 2;
                case 6,  L = 3;
                case 10, L = 0;
                case 11, L = 0;
                otherwise, L = 0;
            end
        end
    end

    function compareTtlAndProceed()
        threshold = 0.5;

        if isnan(ttlFirstMove) || isnan(ttlEnd) || ...
                isnan(remoteTtlFirst) || isnan(remoteTtlEnd)
            doBothFail();
            return;
        end

        ttlStartDiff = abs(ttlFirstMove - remoteTtlFirst);
        ttlEndDiff   = abs(ttlEnd       - remoteTtlEnd);

        if ttlStartDiff <= threshold && ttlEndDiff <= threshold
            doBothSuccess();
        else
            doBothFail();
        end
    end

    function startTask()
        targetSequence   = [7,3,1,5];
        remainingTargets = targetSequence;
        radii            = 0.25;
        circleDiameter   = 0.12;
        circleDiameter2  = 0.12;
        centerHoldDuration       = 0.5;
        targetHoldDuration       = 0.5;
        firstMovementThreshold   = 0.06;
        maxCycles               = 999;
        cyclesCompleted         = 0;
        rxbuf = uint8([]);
        awaitingAck4 = false;
        lastSend4Time = 0;
        ack4Tries = 0;
        targetSyncSentForTrial = 0;
        targetSyncRecvForTrial = 0;

        angles = linspace(0, 2*pi, 9); angles = angles(1:end-1);
        targetCenters = zeros(8, 2);
        for i = 1:length(angles)
            targetCenters(i,1) = radii * cos(angles(i));
            targetCenters(i,2) = radii * sin(angles(i));
        end

        ttlFirstMove = NaN;
        ttlEnd       = NaN;
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
        localCenterDone  = false;
        remoteCenterDone = false;
        mousePath = [];
        remoteTtlFirst = NaN;
        remoteTtlEnd   = NaN;
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
        touchStable = 0; touchHiCnt = 0; touchLoCnt = 0;
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
        axis off; hold on;
        set(fig, 'WindowButtonMotionFcn', @mouseMoved);

        showBlackPanelScreenSync(10);
        drawCircles();
        setInvisibleCursor();
        resetMouseAndDotPositionToCenter();
        showTargetCircles(0);
        cycleStartTime = tic;
        start(timerObj);
    end


    function drawCircles()
        angles = linspace(0, 2*pi, 9); angles = angles(1:end-1);
        for i = 1:length(angles)
            x = radii * cos(angles(i));
            y = radii * sin(angles(i));
            rectangle('Position',[x - circleDiameter/2, ...
                y - circleDiameter/2, ...
                circleDiameter, circleDiameter], ...
                'Curvature',[1,1], ...
                'EdgeColor','w','FaceColor','k', ...
                'LineStyle','--','LineWidth',3, ...
                'UserData', i, ...
                'Tag','TARGET', ...
                'Visible','off');
        end

        rectangle('Position',[-circleDiameter2/2, ...
            -circleDiameter2/2, ...
            circleDiameter2, circleDiameter2], ...
            'Curvature',[1,1], ...
            'EdgeColor','w','FaceColor','w', ...
            'LineStyle','-', 'LineWidth',3, ...
            'UserData',0, ...
            'Tag','CENTER', ...
            'Visible','on');

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
        if isempty(timerObj) || strcmp(timerObj.Running,'off'), return; end
        C = get(ax, 'CurrentPoint');
        x = C(1,1); y = C(1,2);
        x = max(-0.5, min(0.5, x));
        y = max(-0.5, min(0.5, y));

        if isempty(mouseDot) || ~isvalid(mouseDot)
            mouseDot = plot(x, y, 'r.', 'MarkerSize', 100);
        else
            set(mouseDot, 'XData', x, 'YData', y);
        end
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

    function recordMousePos(~, ~)
        if strcmp(timerObj.Running, 'off'), return; end

        x = get(mouseDot, 'XData');
        y = get(mouseDot, 'YData');
        t = toc(cycleStartTime);
        mousePath = [mousePath; x, y, t];
        needTouch = (centerActivated && inCenter(x,y)) || ...
            (targetActivated && inTarget(x,y,currentTarget));

        if needTouch
            scanData = read(daqSession, 1, "OutputFormat", "Matrix");
            rawTouch = scanData(1);
            touchVal = debounceTouch(rawTouch);
        else
            touchVal = debounceTouch(NaN);
        end
        checkFirstMove();
        logic(x, y, touchVal);
        checkTimeout();
        checkRemoteSignal();
    end

    function triggerFail()
        if ~failInProgress
            failInProgress = true;
            sendSignal(tcpObj, 3);
            doBothFail();
        end
    end

    function activateTargetSynced(tgt)
        localSuccess  = false;
        remoteSuccess = false;
        localCenterDone  = false;
        remoteCenterDone = false;
        currentTarget   = double(tgt);
        targetActivated = true;
        centerActivated = false;
        hoverEnterTime = NaN;
        targetReachedOnce = false;
        showTargetCircles(currentTarget);
        firstMove = true;
    end

    function logic(x, y, touchVal)
        tNow = toc(cycleStartTime);
        if centerActivated
            if inCenter(x, y)
                if isnan(centerEnterTime)
                    centerEnterTime = tNow;
                end
                if isnan(centerHoldStartTime)
                    if touchVal == 1
                        centerHoldStartTime = tNow;
                    end
                else
                    if touchVal == 0
                        triggerFail();
                        return;
                    end
                    if ~localCenterDone && (tNow >= centerHoldStartTime + centerHoldDuration)
                        centerexittime   = tNow;
                        localCenterDone = true;
                        lastCenterSent   = trialIndex;
                        safeWrite(tcpObj, [uint8(4), typecast(uint16(trialIndex),'uint8')], 'uint8', 'CENTER');
                        awaitingAck4  = true;
                        lastSend4Time = toc(cycleStartTime);
                        ack4Tries     = 0;
                    end
                end
            else
                if ~isnan(centerEnterTime) || localCenterDone
                    triggerFail();
                    return;
                end
            end
            return;
        end

        if targetActivated
            if inTarget(x, y, currentTarget)
                if isnan(hoverEnterTime)
                    if touchVal == 1
                        hoverEnterTime    = tNow;
                        targetReachedOnce = false;
                    end
                else
                    if touchVal == 0
                        triggerFail();
                        return;
                    end
                    if ~targetReachedOnce && (tNow >= hoverEnterTime + targetHoldDuration)
                        targetReachedOnce = true;
                        sendTTL(2);
                        payload = [ ...
                            uint8(2), ...
                            typecast(uint16(trialIndex),'uint8'), ...
                            typecast([ttlFirstMove, ttlEnd], 'uint8') ...
                            ];
                        safeWrite(tcpObj, payload, 'uint8', 'TARGET_DONE');
                        localSuccess = true;
                        if remoteSuccess
                            compareTtlAndProceed();
                        end
                    end
                end
            else
                if ~isnan(hoverEnterTime)
                    triggerFail();
                    return;
                else
                    hoverEnterTime    = NaN;
                    targetReachedOnce = false;
                end
            end
        end
    end

    function tt = getTotalTime()
        if ~isempty(mousePath) && size(mousePath,2) >= 3
            tt = mousePath(end,3);
        else
            tt = toc(cycleStartTime);
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
        if toc(cycleStartTime) > 8
            handleTimeout();
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
            case 4
                write(daqSession,[0 1 1 0 0]); pause(0.01); write(daqSession,[1 1 0 0 0]);
        end
    end

    function handleTimeout(~)
        if failInProgress, return; end
        failInProgress = true;
        sendSignal(tcpObj, 3);
        doBothFail();
    end

    function resetTarget()
        failInProgress = false;
        trialIndex = cyclesCompleted + 1;
        targetSyncSentForTrial = 0;
        targetSyncRecvForTrial = 0;
        mousePath      = [];
        ttlFirstMove   = NaN;
        ttlEnd         = NaN;
        remoteTtlFirst = NaN;
        remoteTtlEnd   = NaN;
        ttlStartDiff = NaN;
        ttlEndDiff   = NaN;
        lastMoveTime = NaN;
        centerEnterTime     = NaN;
        centerHoldStartTime = NaN;
        hoverEnterTime      = NaN;
        centerexittime      = NaN;
        targetActivated = false;
        centerActivated = true;
        firstMove       = true;
        localCenterDone  = false;
        remoteCenterDone = false;
        lastCenterSent  = 0;
        awaitingAck4  = false;
        lastSend4Time = 0;
        ack4Tries     = 0;
        touchStable = 0; touchHiCnt = 0; touchLoCnt = 0;
        rxbuf = uint8([]);
        resetMouseAndDotPositionToCenter();
        showTargetCircles(0);
        cycleStartTime = tic;
        start(timerObj);
    end

    function recordData = saveMousePathAndTrueCoordinates(pathData, cyclesCompleted, totalTime, status)
        if isempty(pathData)
            disp('mousePath is empty. Skipping save.');
            return;
        end
        targetDir = currentTarget;
        folderName = fullfile(pwd,'S1_L');
        if ~exist(folderName,'dir'), mkdir(folderName); end
        traceFile = fullfile(folderName, ['left' num2str(cyclesCompleted) '.xlsx']);
        writematrix(pathData, traceFile);

        trialData = [cyclesCompleted, targetDir, totalTime, ...
            lastMoveTime,status,ttlFirstMove, ttlEnd,ttlStartDiff, ttlEndDiff,centerexittime];

        summaryFile = fullfile(folderName,'Summary_Data_L1.xlsx');
        if ~isfile(summaryFile)
            header = {'Trial','Target','Dur','FirstMoveTime','Status', ...
                'TTL_FirstMove','TTL_End','TTL_StartDiff','TTL_EndDiff','Centerexittime'};
            writecell(header, summaryFile);
        end
        writematrix(trialData, summaryFile,'WriteMode','append');

        recordData = trialData;
    end
end
