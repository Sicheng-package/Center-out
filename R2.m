function R2()
global targetCenters targetSequence circleDiameter circleDiameter2 radii;
global centerHoldDuration centerEnterTime hoverEnterTime targetHoldDuration centerActivated;
global firstMove FIRSTMOVE_DELTA FIRSTMOVE_FRAMES centerExitPos resetPosition targetReachedOnce;
global targetActivated currentTarget remoteCenterIdx lastCenterSent;
global cyclesCompleted maxCycles mousePath timerObj rxbuf awaitingAck4 lastSend4Time ack4Tries;
global cycleStartTime lastMoveTime remainingTargets;
global mouseDot ax fig screenSize barrierRemoteReady barrierRemoteDone barrierLocalReady barrierLocalDone;
global tcpObj isServer ttlStartDiff ttlEndDiff;
global daqSession centerexittime localCenterDone remoteCenterDone trialIndex;
global localSuccess remoteSuccess failInProgress ttlFirstMove ttlEnd remoteTtlFirst remoteTtlEnd;
global goalSuccesses successCount;
global trialMode uniActiveSide;
global remainingBI remainingUniL remainingUniR;
global passiveOverlay THIS_SIDE;
global SCHEDULE_PATTERN scheduleStep BASE_PATTERN;

goalSuccesses = 360;
successCount  = 0;
isServer      = true;
THIS_SIDE     = 2;  

CONTRA_MOVE_THRESH   = 0.04;
CONTRA_FRAMES_THRESH = 5;
failStatus           = 2;

BASE_PATTERN     = {'bi','uniL','uniR'};
SCHEDULE_PATTERN = BASE_PATTERN(randperm(numel(BASE_PATTERN)));
scheduleStep     = 1;

tcpObj     = initNetwork(isServer);
rxbuf      = uint8([]);
screenSize = get(groot,'ScreenSize');
startTask();

    function tcpObj = initNetwork(serverFlag)
        if serverFlag
            tcpObj = tcpserver("0.0.0.0",30000, ...
                "ConnectionChangedFcn",@serverConnectFcn, ...
                "Timeout",30);
            while ~tcpObj.Connected
                pause(0.01);
            end
        else
            tcpObj = [];
        end
    end

    function serverConnectFcn(~,~)
    end

    function ok = safeWrite(obj,data,dtype)
        ok = true;
        for k = 1:3
            try
                write(obj,data,dtype);
                return;
            catch
                ok = false;
                pause(0.002);
            end
        end
    end

    function sendSignal(obj,val)
        write(obj,uint8(val),'uint8');
    end

    function pumpBarrierBytes()
        n = tcpObj.NumBytesAvailable;
        if n <= 0, return; end
        bytes = read(tcpObj,n,'uint8');
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

    function showBlackPanelScreenSync(duration)
        barrierRemoteReady = false;
        barrierRemoteDone  = false;
        barrierLocalReady  = false;
        barrierLocalDone   = false;
        safeWrite(tcpObj,uint8(10),'uint8');
        barrierLocalReady = true;

        tWait = tic;
        while ~barrierRemoteReady
            pumpBarrierBytes();
            if toc(tWait) > 5, break; end
            pause(0.001);
        end

        blk = uipanel('Parent',fig,'Units','normalized', ...
            'Position',[0 0 1 1], ...
            'BackgroundColor','black','BorderType','none');
        drawnow;
        set(fig,'WindowButtonMotionFcn','');

        t0 = tic;
        while toc(t0) < duration
            pumpBarrierBytes();
            pause(0.001);
        end

        safeWrite(tcpObj,uint8(11),'uint8');
        barrierLocalDone = true;

        tWait = tic;
        while ~barrierRemoteDone
            pumpBarrierBytes();
            if toc(tWait) > 5, break; end
            pause(0.001);
        end

        delete(blk);
        set(fig,'WindowButtonMotionFcn',@mouseMoved);
    end

    function startTask()
        targetSequence   = [7 3 1 5];
        remainingTargets = targetSequence;
        radii           = 0.25;
        circleDiameter  = 0.15;
        circleDiameter2 = 0.08;
        centerHoldDuration = 0.8;
        targetHoldDuration = 1;
        FIRSTMOVE_DELTA    = 0.01;
        FIRSTMOVE_FRAMES   = 5;
        maxCycles       = 999;
        cyclesCompleted = 0;
        rxbuf = uint8([]);
        awaitingAck4  = false;
        lastSend4Time = 0;
        ack4Tries     = 0;
        ttlFirstMove   = NaN;
        ttlEnd         = NaN;
        remoteTtlFirst = NaN;
        remoteTtlEnd   = NaN;
        ttlStartDiff   = NaN;
        ttlEndDiff     = NaN;
        centerActivated   = false; 
        centerEnterTime   = NaN;
        centerexittime    = NaN;
        hoverEnterTime    = NaN;
        firstMove         = true;
        targetActivated   = false;
        targetReachedOnce = false;
        localCenterDone  = false;
        remoteCenterDone = false;
        mousePath      = [];
        lastMoveTime   = NaN;
        resetPosition  = [0 0];
        failInProgress = false;
        failStatus     = 2;
        localSuccess  = false;
        remoteSuccess = false;
        trialIndex    = 0;
        trialMode     = 1;
        uniActiveSide = 0;
        remainingBI   = targetSequence(:)';
        remainingUniL = targetSequence(randperm(numel(targetSequence)));
        remainingUniR = targetSequence(randperm(numel(targetSequence)));

        angles = linspace(0,2*pi,9);
        angles = angles(1:end-1);
        targetCenters = zeros(8,2);
        for i = 1:8
            targetCenters(i,1) = radii*cos(angles(i));
            targetCenters(i,2) = radii*sin(angles(i));
        end

        remoteCenterIdx = -1;
        lastCenterSent  = 0;
        barrierRemoteReady = false;
        barrierRemoteDone  = false;
        barrierLocalReady  = false;
        barrierLocalDone   = false;
        daqSession = daq("ni");
        addoutput(daqSession,"Dev4","port0/line0:4","Digital");

        fig = figure('Color','black','Pointer','custom', ...
            'Units','normalized','Position',[0 0 1 1], ...
            'MenuBar','none','ToolBar','none','WindowState','fullscreen');

        ax = axes('Parent',fig,'Color','black', ...
            'Units','normalized','Position',[0 0 1 1], ...
            'DataAspectRatio',[1 1 1]);
        axis off; hold on;

        set(fig,'WindowButtonMotionFcn',@mouseMoved);

        passiveOverlay = uipanel('Parent',fig,'Units','normalized', ...
            'Position',[0 0 1 1], ...
            'BackgroundColor','black','BorderType','none','Visible','off');

        timerObj = timer('TimerFcn',@recordMousePos, ...
            'Period',0.001,'ExecutionMode','fixedRate');

        showBlackPanelScreenSync(20);
        drawCircles();
        setInvisibleCursor();
        resetMouseAndDotPositionToCenter();
        showTargetCircles(0);
        cycleStartTime = tic;
        start(timerObj);
        sendTTL(3);
        planNextTrial();
    end

    function planNextTrial()
        tag = SCHEDULE_PATTERN{scheduleStep};

        switch lower(tag)
            case 'bi'
                trialMode     = 1;
                uniActiveSide = 0;
                if isempty(remainingBI)
                    remainingBI = targetSequence(:)';
                end
                dir = remainingBI(1);

            case 'unil'
                trialMode     = 2;
                uniActiveSide = 1;
                if isempty(remainingUniL)
                    remainingUniL = targetSequence(randperm(numel(targetSequence)));
                end
                dir = remainingUniL(1);

            case 'unir'
                trialMode     = 3;
                uniActiveSide = 2;
                if isempty(remainingUniR)
                    remainingUniR = targetSequence(randperm(numel(targetSequence)));
                end
                dir = remainingUniR(1);

            otherwise
                trialMode     = 1;
                uniActiveSide = 0;
                if isempty(remainingBI)
                    remainingBI = targetSequence(:)';
                end
                dir = remainingBI(1);
        end

        trialIndex    = trialIndex + 1;
        currentTarget = dir;

        meta = [ ...
            uint8(6); ...
            typecast(uint16(trialIndex),'uint8')'; ...
            uint8(trialMode); ...
            uint8(uniActiveSide); ...
            uint8(currentTarget) ...
        ];
        safeWrite(tcpObj,meta,'uint8');
        applyTrialMeta(trialMode,uniActiveSide,currentTarget);
        centerActivated   = isActiveSide();
        centerEnterTime   = NaN;
        centerexittime    = NaN;
        hoverEnterTime    = NaN;
        firstMove         = true;
        targetReachedOnce = false;
        localCenterDone   = false;
        remoteCenterDone  = false;
        ttlFirstMove      = NaN;
        ttlEnd            = NaN;
        remoteTtlFirst    = NaN;
        remoteTtlEnd      = NaN;
        ttlStartDiff      = NaN;
        ttlEndDiff        = NaN;
        lastMoveTime      = NaN;
        resetPosition     = [0 0];
        failInProgress    = false;
        failStatus        = 2;
        localSuccess      = false;
        remoteSuccess     = false;
        mousePath         = [];
    end

    function updateQueuesOnSuccess()
        switch trialMode
            case 1
                if ~isempty(remainingBI)
                    remainingBI(1) = [];
                    if isempty(remainingBI)
                        remainingBI = targetSequence(:)';
                    end
                end
            case 2
                if ~isempty(remainingUniL)
                    remainingUniL(1) = [];
                    if isempty(remainingUniL)
                        remainingUniL = targetSequence(randperm(numel(targetSequence)));
                    end
                end
            case 3
                if ~isempty(remainingUniR)
                    remainingUniR(1) = [];
                    if isempty(remainingUniR)
                        remainingUniR = targetSequence(randperm(numel(targetSequence)));
                    end
                end
        end
        scheduleStep = scheduleStep + 1;
        if scheduleStep > numel(SCHEDULE_PATTERN)
            SCHEDULE_PATTERN = BASE_PATTERN(randperm(numel(BASE_PATTERN)));
            scheduleStep = 1;
        end
    end

    function mouseMoved(~,~)
        % if isempty(ax) || ~ishandle(ax)
        %     return;
        % end
        if isempty(timerObj) || strcmp(timerObj.Running,'off')
            return;
        end
        C = get(ax,'CurrentPoint');
        x = C(1,1);
        y = C(1,2);
        x = max(-0.5,min(0.5,x));
        y = max(-0.5,min(0.5,y));
        if isempty(mouseDot) || ~isvalid(mouseDot)
            mouseDot = plot(x,y,'r.','MarkerSize',100);
        else
            set(mouseDot,'XData',x,'YData',y);
        end
    end

    function recordMousePos(~,~)
        if strcmp(timerObj.Running,'off')
            return;
        end

        x = get(mouseDot,'XData');
        y = get(mouseDot,'YData');
        t = toc(cycleStartTime);
        mousePath = [mousePath; x,y,t];
        checkFirstMove();
        logic(x,y);
        checkContraMove(x,y);
        checkTimeout();
        try
            checkRemoteSignal();
        catch
        end
    end

    function a = isActiveSide()
        a = (trialMode == 1) || ...
            (trialMode == 2 && THIS_SIDE == 1) || ...
            (trialMode == 3 && THIS_SIDE == 2);
    end

    function p = isPassiveSide()
        p = (trialMode ~= 1) && ~isActiveSide();
    end

    function logic(x,y)
        tNow = toc(cycleStartTime);
        if centerActivated && isActiveSide()
            if inCenter(x,y)
                if isnan(centerEnterTime)
                    centerEnterTime = tNow;
                elseif tNow >= centerEnterTime + centerHoldDuration
                    centerActivated = false;
                    centerexittime  = tNow;
                    centerEnterTime = NaN;
                    localCenterDone = true;
                    centerExitPos   = [get(mouseDot,'XData'), get(mouseDot,'YData')];
                    if isActiveSide()
                        showTargetCircles(currentTarget);
                        targetActivated = true;
                    end
                end
            else
                if ~isnan(centerEnterTime)
                    sendSignal(tcpObj,3);
                    failStatus = 2;
                    doBothFail();
                    return;
                end
            end
        end

        if ~centerActivated && isActiveSide()
            if targetActivated && inTarget(x,y,currentTarget)
                if isnan(hoverEnterTime)
                    hoverEnterTime    = tNow;
                    targetReachedOnce = false;
                elseif ~targetReachedOnce && tNow >= hoverEnterTime + targetHoldDuration
                    targetReachedOnce = true;
                    sendTTL(2);
                    payload = [ ...
                        uint8(2); ...
                        typecast(uint16(trialIndex),'uint8')'; ...
                        typecast([ttlFirstMove, ttlEnd],'uint8')' ...
                    ];
                    safeWrite(tcpObj,payload,'uint8');
                    localSuccess = true;
                    if trialMode == 1
                        if remoteSuccess
                            compareTtlAndProceed();
                        end
                    else
                        doBothSuccess();
                    end
                end
            else
                hoverEnterTime = NaN;
            end
        end
    end

    function checkFirstMove()
        persistent aboveCount
        if isempty(aboveCount)
            aboveCount = 0;
        end

        if firstMove && ~centerActivated && targetActivated && isActiveSide()
            pos = [get(mouseDot,'XData'), get(mouseDot,'YData')];
            if norm(pos - centerExitPos) > FIRSTMOVE_DELTA
                aboveCount = aboveCount + 1;
                if aboveCount >= FIRSTMOVE_FRAMES
                    lastMoveTime = toc(cycleStartTime);
                    sendTTL(1);
                    firstMove = false;
                    aboveCount = 0;
                end
            else
                aboveCount = 0;
            end
        else
            aboveCount = 0;
        end
    end

    function checkContraMove(x,y)
        persistent contraCount
        if isempty(contraCount)
            contraCount = 0;
        end

        if ~isPassiveSide()
            contraCount = 0;
            return;
        end

        d = hypot(x - resetPosition(1), y - resetPosition(2));
        if d > CONTRA_MOVE_THRESH
            contraCount = contraCount + 1;
            if contraCount >= CONTRA_FRAMES_THRESH
                if failInProgress
                    return;
                end
                failInProgress = true;
                failStatus = 3;
                sendSignal(tcpObj,3);
                doBothFail();
            end
        else
            contraCount = 0;
        end
    end

    function checkTimeout()
        if ~centerActivated && targetActivated && isActiveSide()
            if toc(cycleStartTime) > 8
                handleTimeout();
            end
        end
    end

    function handleTimeout()
        if failInProgress
            return;
        end
        failInProgress = true;
        failStatus = 2;
        sendSignal(tcpObj,3);
        doBothFail();
    end

    function sendTTL(signalType)
        if isempty(daqSession) || ~isvalid(daqSession)
            return;
        end
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

    function checkRemoteSignal()
        n = tcpObj.NumBytesAvailable;
        if n > 0
            rxbuf = [rxbuf; read(tcpObj,n,'uint8')];
        end

        while true
            if numel(rxbuf) < 1, break; end
            op = rxbuf(1);
            need = payloadLen(op);
            if numel(rxbuf) < 1+need, break; end

            payload = rxbuf(2:1+need);
            rxbuf   = rxbuf(2+need:end);

            switch op
                case 2
                    rTrial = double(typecast(uint8(payload(1:2)),'uint16'));
                    if rTrial ~= trialIndex
                        continue;
                    end
                    times = typecast(uint8(payload(3:end)),'double');
                    remoteTtlFirst = times(1);
                    remoteTtlEnd   = times(2);
                    remoteSuccess  = true;
                    if trialMode == 1
                        if localSuccess
                            compareTtlAndProceed();
                        end
                    else
                        doBothSuccess();
                    end

                case 3
                    remoteSuccess = false;
                    if ~failInProgress
                        failInProgress = true;
                        doBothFail();
                    end

                case 4
                    rTrial = double(typecast(uint8(payload(1:2)),'uint16'));
                    write(tcpObj,[uint8(5), typecast(uint16(rTrial),'uint8')],'uint8');
                    remoteCenterDone = true;
                    remoteCenterIdx  = max(remoteCenterIdx,rTrial);

                case 5
                case 6
                case 10
                    barrierRemoteReady = true;
                case 11
                    barrierRemoteDone  = true;
                otherwise
            end
        end

        function Lp = payloadLen(op_)
            switch op_
                case 2,  Lp = 18;
                case 3,  Lp = 0;
                case 4,  Lp = 2;
                case 5,  Lp = 2;
                case 6,  Lp = 5;
                case 10, Lp = 0;
                case 11, Lp = 0;
                otherwise, Lp = 0;
            end
        end
    end

    function compareTtlAndProceed()
        threshold = 0.5;

        if isnan(ttlFirstMove) || isnan(ttlEnd) || ...
           isnan(remoteTtlFirst) || isnan(remoteTtlEnd)
            failStatus = 2;
            doBothFail();
            return;
        end

        ttlStartDiff = abs(ttlFirstMove - remoteTtlFirst);
        ttlEndDiff   = abs(ttlEnd       - remoteTtlEnd);

        if ttlStartDiff <= threshold && ttlEndDiff <= threshold
            doBothSuccess();
        else
            failStatus = 2;
            doBothFail();
        end
    end

    function doBothSuccess()
        stop(timerObj);
        totalTime = getTotalTime();
        cyclesCompleted = cyclesCompleted + 1;
        saveMousePathAndTrueCoordinates(mousePath,cyclesCompleted,totalTime,1);
        successCount = successCount + 1;
        updateQueuesOnSuccess();
        showBlackPanelScreenSync(3);
        if successCount >= goalSuccesses || cyclesCompleted >= maxCycles
            stop(timerObj); delete(timerObj); close(fig);
            return;
        end
        resetForNextTrial();
    end

    function doBothFail()
        stop(timerObj);
        totalTime = getTotalTime();
        cyclesCompleted = cyclesCompleted + 1;
        saveMousePathAndTrueCoordinates(mousePath,cyclesCompleted,totalTime,failStatus);
        showBlackPanelScreenSync(3);
        if successCount >= goalSuccesses || cyclesCompleted >= maxCycles
            stop(timerObj); delete(timerObj); close(fig);
            return;
        end
        resetForNextTrial();
    end

    function resetForNextTrial()
        mousePath        = [];
        ttlFirstMove     = NaN;
        ttlEnd           = NaN;
        remoteTtlFirst   = NaN;
        remoteTtlEnd     = NaN;
        ttlStartDiff     = NaN;
        ttlEndDiff       = NaN;
        lastMoveTime     = NaN;
        centerEnterTime  = NaN;
        hoverEnterTime   = NaN;
        centerexittime   = NaN;
        centerExitPos    = [0 0];
        centerActivated  = false;
        targetActivated  = false;
        localCenterDone  = false;
        remoteCenterDone = false;
        firstMove        = true;
        targetReachedOnce = false;
        failInProgress   = false;
        failStatus       = 2;
        localSuccess     = false;
        remoteSuccess    = false;

        while tcpObj.NumBytesAvailable > 0
            read(tcpObj,tcpObj.NumBytesAvailable,'uint8');
        end
        rxbuf = uint8([]);
        resetMouseAndDotPositionToCenter();
        showTargetCircles(0);
        cycleStartTime = tic;
        start(timerObj);
        sendTTL(3);
        planNextTrial();
    end

    function totalTime = getTotalTime()
        if ~isempty(mousePath) && size(mousePath,2) >= 3
            totalTime = mousePath(end,3);
        else
            totalTime = toc(cycleStartTime);
        end
    end

    function drawCircles()
        angles = linspace(0,2*pi,9);
        angles = angles(1:end-1);
        for i = 1:8
            x = radii*cos(angles(i));
            y = radii*sin(angles(i));
            rectangle('Position',[x-circleDiameter/2, ...
                                  y-circleDiameter/2, ...
                                  circleDiameter, circleDiameter], ...
                      'Curvature',[1,1], ...
                      'EdgeColor','w','FaceColor','k', ...
                      'LineStyle','-','LineWidth',3, ...
                      'UserData',i, ...
                      'Visible','off');
        end

        rectangle('Position',[-circleDiameter2/2, -circleDiameter2/2, ...
                               circleDiameter2, circleDiameter2], ...
                  'Curvature',[1,1], ...
                  'EdgeColor','y','FaceColor','y', ...
                  'LineStyle','-', 'LineWidth',3, ...
                  'Visible','on');

        xlim([-0.5,0.5]);
        ylim([-0.5,0.5]);
    end

    function setInvisibleCursor()
        transparentCursor = NaN(16,16);
        hotspot = [8,8];
        set(fig,'Pointer','custom', ...
            'PointerShapeCData',transparentCursor, ...
            'PointerShapeHotSpot',hotspot);
    end

    function setPassiveOverlay(vis)
        if vis
            set(passiveOverlay,'Visible','on');
        else
            set(passiveOverlay,'Visible','off');
        end
    end

    function applyTrialMeta(m,side,dir)
        trialMode     = m;
        uniActiveSide = side;
        currentTarget = dir;
        if trialMode == 2      % uniL
            setPassiveOverlay(true);   
            showTargetCircles(0);
            targetActivated = false;
        elseif trialMode == 3  % uniR
            setPassiveOverlay(false);   
            showTargetCircles(0);      
            targetActivated = false;
        else                   % bi
            setPassiveOverlay(false);
            showTargetCircles(0);
            targetActivated = false;
        end

        firstMove         = true;
        targetReachedOnce = false;
        hoverEnterTime    = NaN;
        localSuccess      = false;
        remoteSuccess     = false;
        centerActivated   = isActiveSide();
        centerEnterTime   = NaN;
        centerexittime    = NaN;
    end

    function resetMouseAndDotPositionToCenter()
        if isempty(mouseDot) || ~isvalid(mouseDot)
            mouseDot = plot(0,0,'r.','MarkerSize',100);
        end
        figPos = get(fig,'Position');
        pixPos = getpixelposition(ax,true);

        axCenterX = figPos(1)*screenSize(3) + pixPos(1) + pixPos(3)/2;
        axCenterY = screenSize(4) - (figPos(2)*screenSize(4) + pixPos(2) + pixPos(4)/2);
        robot = java.awt.Robot;
        robot.mouseMove(round(axCenterX),round(axCenterY));
        mousePath     = [];
        resetPosition = [0 0];
        set(mouseDot,'XData',0,'YData',0);
    end

    function showTargetCircles(targetNum)
        objs = findall(ax,'Type','rectangle');
        objs = objs(:);

        if isempty(objs), return; end

        fc = get(objs,'FaceColor');
        if ~iscell(fc), fc = {fc}; end

        isCenter = cellfun(@(c) isequal(c,[1 1 0]),fc);
        centerObj  = objs(isCenter);
        circleObjs = objs(~isCenter);

        if targetNum == 0
            if ~isempty(centerObj)
                set(centerObj,'Visible','on');
            end
            if ~isempty(circleObjs)
                set(circleObjs,'Visible','off');
            end
            return;
        end

        if ~isempty(centerObj)
            set(centerObj,'Visible','off');
        end

        for i = 1:numel(circleObjs)
            idx = get(circleObjs(i),'UserData');
            if isempty(idx) || ~isscalar(idx)
                continue;
            end
            if idx == targetNum
                set(circleObjs(i),'Visible','on', ...
                    'FaceColor','w','EdgeColor','w', ...
                    'LineStyle','-','LineWidth',3);
            else
                set(circleObjs(i),'Visible','off');
            end
        end
    end

    function tf = inCenter(x,y)
        tf = hypot(x,y) < 0.5*circleDiameter2;
    end

    function tf = inTarget(x,y,targetNum)
        if targetNum == 0
            tf = false;
            return;
        end
        c = targetCenters(targetNum,:);
        tf = hypot(x-c(1),y-c(2)) < 0.5*circleDiameter;
    end

    function recordData = saveMousePathAndTrueCoordinates(pathData,trialID,totalTime,status)
        if isempty(pathData)
            recordData = [];
            return;
        end

        if isempty(currentTarget) || isnan(currentTarget)
            targetDir = -1;
        else
            targetDir = currentTarget;
        end
        
        folderName = fullfile(pwd,'R');
        if ~exist(folderName,'dir')
            mkdir(folderName);
        end

        traceFile = fullfile(folderName,['right' num2str(trialID) '.xlsx']);
        writematrix(pathData,traceFile);

        isPassive = (trialMode ~= 1 && ...
                    ((trialMode == 2 && THIS_SIDE ~= 1) || ...
                     (trialMode == 3 && THIS_SIDE ~= 2)));

        trialData = [ ...
            trialID, targetDir, totalTime, lastMoveTime, status, ...
            ttlFirstMove, ttlEnd, ttlStartDiff, ttlEndDiff, ...
            centerexittime, ...
            trialMode, uniActiveSide, isPassive ...
        ];

        summaryFile = fullfile(folderName,'Summary_R.xlsx');
        if ~isfile(summaryFile)
            header = {'Trial','Target','Dur','FirstMoveTime', ...
                      'Status(1=succ,2=fail,3=contraMove)', ...
                      'TTL_FirstMove','TTL_End','TTL_StartDiff','TTL_EndDiff', ...
                      'CenterExitTime', ...
                      'Mode(1=BI,2=UNI-L,3=UNI-R)', ...
                      'UniSide(0=Both,1=L,2=R)','Passive(0/1)'};
            writecell(header,summaryFile);
        end

        writematrix(trialData,summaryFile,'WriteMode','append');
        recordData = trialData;
    end
end
