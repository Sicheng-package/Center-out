function unimanual_R_touch(goalSuccessesInput)
screenSize = get(groot, 'ScreenSize');
global targetCenters targetSequence circleDiameter circleDiameter2 radii;
global centerHoldDuration centerActivated;
global firstMove firstMovementThreshold resetPosition targetReachedOnce;
global targetActivated currentTarget hoverStartTime;
global cyclesCompleted maxCycles mousePath timerObj;
global cycleStartTime lastMoveTime remainingTargets;
global mouseDot ax fig ttlFirstMove ttlEnd daqSession;
global centerEnterTime hoverEnterTime;
global targetHoldDuration;
global goalSuccesses successCount;
global centerHoldStartTime;

TOUCH_ACTIVE_LEVEL = 1;
TOUCH_FRAMES       = 5;
touchStable = 0;
touchHiCnt  = 0;
touchLoCnt  = 0;

if nargin < 1
    goalSuccesses = 100;
else
    goalSuccesses = goalSuccessesInput;
end
successCount = 0;

startTask();

    function startTask()
        targetSequence          = [1,3,5,7];
        radii                   = 0.25;
        circleDiameter          = 0.1;
        circleDiameter2         = 0.1;
        centerHoldDuration      = 1;
        targetHoldDuration      = 1;
        centerEnterTime         = NaN;
        centerHoldStartTime     = NaN;
        hoverEnterTime          = NaN;
        firstMovementThreshold  = 0.05;
        maxCycles               = 999;
        cyclesCompleted         = 0;
        angles = linspace(0, 2*pi, 9);
        angles = angles(1:end-1);
        targetCenters = zeros(8, 2);
        for i = 1:length(angles)
            targetCenters(i, 1) = radii * cos(angles(i));
            targetCenters(i, 2) = radii * sin(angles(i));
        end
        centerActivated     = true;
        firstMove           = true;
        targetActivated     = false;
        hoverStartTime      = [];
        targetReachedOnce   = false;
        mousePath           = [];
        lastMoveTime        = 0;
        resetPosition       = [0, 0];
        remainingTargets = targetSequence(randperm(length(targetSequence)));
        daqSession = daq("ni");
        addoutput(daqSession, "Dev4", "port0/line0:4", "Digital");
        addinput(daqSession,  "Dev4", "port1/line3",   "Digital");

        timerObj = timer('TimerFcn', @recordMousePos, ...
                         'Period', 0.004, 'ExecutionMode', 'fixedRate');

        fig = figure('Color','black','Pointer','custom', ...
                     'Units','normalized','Position',[0 0 1 1], ...
                     'MenuBar','none','ToolBar','none','WindowState','fullscreen');
        ax  = axes('Parent', fig, ...
                   'Color','black','Units','normalized','Position',[0 0 1 1], ...
                   'DataAspectRatio',[1 1 1]);
        axis off; hold on;
        set(fig, 'WindowButtonMotionFcn', @mouseMoved);
        showBlackPanelScreen(10);
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
            rectangle('Position',[x - circleDiameter/2, ...
                y - circleDiameter/2, ...
                circleDiameter, circleDiameter], ...
                'Curvature',[1,1],'EdgeColor','w','FaceColor','k', ...
                'LineStyle','--','LineWidth',3,'UserData',i, ...
                'Visible','off');
        end

        rectangle('Position', [-circleDiameter2/2, ...
            -circleDiameter2/2, ...
            circleDiameter2, circleDiameter2], ...
            'Curvature',[1,1], ...
            'EdgeColor','Y','FaceColor','Y', ...
            'LineStyle','-','LineWidth',3,'Visible','on');

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
        mousePath      = [];
        resetPosition  = [0, 0];
        set(mouseDot, 'XData',0,'YData',0);
    end

    function showTargetCircles(targetNum)
        objs = findall(ax, 'Type','rectangle');
        objs = objs(:);
        fc = get(objs,'FaceColor');
        if ~iscell(fc), fc = {fc}; end
        isCenter = cellfun(@(c) isequal(c,[1 1 0]), fc);
        centerObj  = objs(isCenter);
        circleObjs = objs(~isCenter);
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

    function logic(x, y, touchVal)
        tNow = toc(cycleStartTime);
        if centerActivated
            if inCenter(x,y)
                if isnan(centerEnterTime)
                    centerEnterTime = tNow;
                end
                if isnan(centerHoldStartTime)
                    if touchVal == 1
                        centerHoldStartTime = tNow;
                    end
                else
                    if (touchVal == 0)
                        handleTimeout(2);
                        return;
                    elseif tNow >= centerHoldStartTime + centerHoldDuration
                        centerActivated     = false;
                        centerEnterTime     = NaN;
                        centerHoldStartTime = NaN;
                        activateNextTarget();
                        drawnow;
                    end
                end

            else
                if ~isnan(centerEnterTime)
                    handleTimeout(2);
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
                        % hoverEnterTime    = NaN;
                        % targetReachedOnce = false;
                        handleTimeout(2);
                        return;
                    elseif ~targetReachedOnce && tNow >= hoverEnterTime + targetHoldDuration
                        targetReachedOnce = true;
                        sendTTL(2);
                        stop(timerObj);
                        cyclesCompleted = cyclesCompleted + 1;
                        totalTime = getTotalTime();
                        saveMousePathAndTrueCoordinates(mousePath, cyclesCompleted, totalTime, 3);
                        successCount = successCount + 1;
                        showBlackPanelScreen(3);
                        mousePath = [];
                        if successCount >= goalSuccesses || cyclesCompleted >= maxCycles
                            delete(timerObj);
                            close(fig);
                            return;
                        else
                            resetTarget();
                        end
                    end
                end
            else
                if ~isnan(hoverEnterTime)
                    handleTimeout(2);
                    return;
                else
                    hoverEnterTime    = NaN;
                    targetReachedOnce = false;
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

    function activateNextTarget()
        if ~isempty(remainingTargets)
            currentTarget = remainingTargets(1);
            remainingTargets(1) = [];
        else
            newOrder = targetSequence(randperm(length(targetSequence)));
            remainingTargets = newOrder;
            currentTarget    = remainingTargets(1);
            remainingTargets(1) = [];
        end

        targetActivated = true;
        showTargetCircles(currentTarget);
        firstMove = true;
    end

    function checkFirstMove()
        persistent aboveThresholdCount
        if isempty(aboveThresholdCount), aboveThresholdCount = 0; end

        consecutiveFrames = 5;
        if firstMove && ~centerActivated && targetActivated
            pos   = [get(mouseDot,'XData'), get(mouseDot,'YData')];
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
            handleTimeout(2);
        end
    end

    function sendTTL(signalType)
        if isempty(daqSession) || ~isvalid(daqSession), return; end
        nowRel = toc(cycleStartTime);
        switch signalType
            case 1
                ttlFirstMove = nowRel;
                write(daqSession,[1 0 0 1 0]); write(daqSession,[1 1 0 0 0]);
            case 2
                ttlEnd = nowRel;
                write(daqSession,[0 1 0 0 1]); write(daqSession,[1 1 0 0 0]);
            case 3
                write(daqSession,[1 1 1 0 0]); write(daqSession,[1 1 0 0 0]);
        end
    end

    function tt = getTotalTime()
        if ~isempty(mousePath) && size(mousePath,2) >= 3
            tt = mousePath(end,3);
        else
            tt = toc(cycleStartTime);
        end
    end

    function handleTimeout(timeoutType)
        cyclesCompleted = cyclesCompleted + 1;
        totalTime = getTotalTime();
        if timeoutType == 2
            saveMousePathAndTrueCoordinates(mousePath, cyclesCompleted, totalTime, 2);
        else
            saveMousePathAndTrueCoordinates(mousePath, cyclesCompleted, totalTime, 1);
        end
        if ~ismember(currentTarget, remainingTargets)
            remainingTargets = [remainingTargets, currentTarget];
        end

        stop(timerObj);
        showBlackPanelScreen(3);

        if cyclesCompleted >= maxCycles
            delete(timerObj);
            close(fig);
        else
            resetTarget();
        end
    end

    function resetTarget()
        centerEnterTime       = NaN;
        centerHoldStartTime   = NaN;
        hoverEnterTime        = NaN;
        mousePath             = [];
        ttlFirstMove          = NaN;
        ttlEnd                = NaN;
        lastMoveTime          = NaN;
        targetActivated       = false;
        centerActivated       = true;
        firstMove             = true;
        touchStable = 0; touchHiCnt = 0; touchLoCnt = 0;
        resetMouseAndDotPositionToCenter();
        showTargetCircles(0);
        cycleStartTime  = tic;
        start(timerObj);
        sendTTL(3);
    end

 function recordMousePos(~, ~)
        if strcmp(timerObj.Running, 'off'), return; end
        x = get(mouseDot, 'XData');
        y = get(mouseDot, 'YData');
        t = toc(cycleStartTime);
        needTouch = (centerActivated && inCenter(x,y)) || ...
            (targetActivated && inTarget(x,y,currentTarget));
        if needTouch
            scanData = read(daqSession, 1, "OutputFormat", "Matrix");
            rawTouch = scanData(1);
            touchVal = debounceTouch(rawTouch);
        else
            touchVal = debounceTouch(NaN);
        end
        mousePath = [mousePath; x, y, t];
        checkFirstMove();
        logic(x, y, touchVal);
        checkTimeout();
    end

    function recordData = saveMousePathAndTrueCoordinates(pathData, cyclesCompleted, totalTime, status)
        if isempty(pathData)
            return;
        end
        targetDir = currentTarget;
        folderName = fullfile(pwd,'S1R');
        if ~exist(folderName,'dir'), mkdir(folderName); end
        traceFile = fullfile(folderName, ['right' num2str(cyclesCompleted) '.xlsx']);
        writematrix(pathData, traceFile);
        trialData = [cyclesCompleted, targetDir, totalTime, ...
            lastMoveTime, status, ttlFirstMove, ttlEnd, centerHoldStartTime];

        summaryFile = fullfile(folderName,'Summary_Data.xlsx');
        if ~isfile(summaryFile)
            header = {'Trial','Target','Dur','FirstMoveTime','Status', ...
                'TTL_FirstMove','TTL_End','CenterHoldStartTime'};
            writecell(header, summaryFile);
        end
        writematrix(trialData, summaryFile,'WriteMode','append');
        recordData = trialData;
    end

    function showBlackPanelScreen(duration)
        originalColor       = get(fig,'Color');
        originalUnits       = get(fig,'Units');
        originalWindowState = get(fig,'WindowState');
        set(fig,'WindowState','fullscreen');

        blackPanel = uipanel('Parent',fig, ...
            'Units','normalized','Position',[0 0 1 1], ...
            'BackgroundColor','black','BorderType','none');
        uistack(blackPanel,'top');
        drawnow;

        set(fig, 'WindowButtonMotionFcn','');
        set(fig, 'WindowButtonDownFcn','');
        set(fig, 'WindowButtonUpFcn','');

        startTime = tic;
        while toc(startTime) < duration
            drawnow;
        end
        delete(blackPanel);
        set(fig,'Color', originalColor);
        set(fig,'Units', originalUnits);
        set(fig,'WindowState', originalWindowState);
        set(fig, 'WindowButtonMotionFcn', @mouseMoved);
    end
end
