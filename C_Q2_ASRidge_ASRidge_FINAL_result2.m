%% ============================================================
% 2026 C题 问题2 —— 最终提交版
%
% 预测模型：
%
% 负载：AS-Ridge
% 光伏：AS-Ridge
%
% ============================================================
% 模型逻辑：
%
% AS-Ridge负载预测
% +
% AS-Ridge光伏预测
% +
% 最近30日净负荷历史残差Q0.8风险校准
% +
% 每日0:00制定全天计划
% +
% 严格逐10min因果实际执行
% +
% 紧急购电价格 = 正常电价的5倍
%
% ============================================================
% 储能：
%
% 1200 <= SOC <= 10800 kWh
%
% 最大充电功率 5000 kW
% 最大放电功率 5000 kW
%
% eta_ch = eta_dis = 0.9
%
% ============================================================
% 当前实验设定：
%
% 1. FORCE_FINAL_SOC_6000 = false
%
% 2. cyclePenalty = 0
%
% 3. 不设置充放电互斥约束
%
% 4. 允许：
%       Wch > 0
%       Wdis > 0
%    同时出现
%
% ============================================================
% 最终自动写入：
%
% 附件5\result2.xlsx
%
%% ============================================================

clear;
clc;
close all;


fprintf('====================================================\n');
fprintf(' C题问题2 最终版\n');
fprintf(' 负载：AS-Ridge\n');
fprintf(' 光伏：AS-Ridge\n');
fprintf(' Q0.8 + 因果回放 + no-CD-mutex\n');
fprintf('====================================================\n\n');


%% ============================================================
% 0. 开关
%% ============================================================

FORCE_FINAL_SOC_6000 = false;

MIN_HISTORY_DAYS = 7;

ROLLING_WINDOW_DAYS = 30;

Q_LEVEL = 0.80;

WRITE_RESULT2 = true;


%% ============================================================
% 1. 路径
%% ============================================================

baseDir = ...
    'E:\数模\2026年正式比赛\CUMCM2026Problems\C题\附件';


%% ------------------------------------------------------------
% 16组合程序已经生成的四模型预测缓存
%
% predLoad(:,:,1) = AS-Ridge负载
% predPV(:,:,1)   = AS-Ridge光伏
%% ------------------------------------------------------------

predictionFile = ...
    fullfile( ...
    baseDir, ...
    'Q2_16combo_4models_predictions.mat');


dataFile = ...
    fullfile( ...
    baseDir, ...
    '附件2.xlsx');


priceFile = ...
    fullfile( ...
    baseDir, ...
    '附件1.xlsx');


resultFile = ...
    fullfile( ...
    baseDir, ...
    '附件5', ...
    'result2.xlsx');


matFile = ...
    fullfile( ...
    baseDir, ...
    'Q2_ASRidge_ASRidge_FINAL.mat');


%% ============================================================
% 2. 文件检查
%% ============================================================

if ~isfile(predictionFile)

    error( ...
        ['找不到四模型预测缓存：\n%s\n\n', ...
        '请确认之前成功跑16组合时生成的', ...
        'Q2_16combo_4models_predictions.mat仍然存在。'], ...
        predictionFile);

end


if ~isfile(dataFile)

    error( ...
        '找不到附件2：\n%s', ...
        dataFile);

end


if ~isfile(priceFile)

    error( ...
        '找不到附件1：\n%s', ...
        priceFile);

end


if ~isfile(resultFile)

    error( ...
        '找不到官方result2.xlsx：\n%s', ...
        resultFile);

end


%% ============================================================
% 3. 读取四模型预测
%% ============================================================

fprintf('正在读取四模型预测缓存...\n');


P = ...
    load(predictionFile);


if ~isfield(P,'predLoad') ...
        || ...
        ~isfield(P,'predPV')

    error( ...
        '预测MAT缺少predLoad或predPV');

end


if ~isequal( ...
        size(P.predLoad), ...
        [334,144,4])

    error( ...
        'predLoad应为334×144×4，目前为%s', ...
        mat2str(size(P.predLoad)));

end


if ~isequal( ...
        size(P.predPV), ...
        [334,144,4])

    error( ...
        'predPV应为334×144×4，目前为%s', ...
        mat2str(size(P.predPV)));

end


%% ============================================================
% ★选择AS-Ridge
%
% 模型顺序：
%
% 1 AS-Ridge
% 2 QAR
% 3 Q-Ridge
% 4 AS-SARIMA
%% ============================================================

ASRIDGE_INDEX = 1;


predLoad = ...
    P.predLoad(:,:,ASRIDGE_INDEX);


predPV = ...
    P.predPV(:,:,ASRIDGE_INDEX);


fprintf('负载预测：AS-Ridge\n');
fprintf('光伏预测：AS-Ridge\n\n');


%% ============================================================
% 4. 读取真实负荷和真实光伏
%% ============================================================

fprintf('正在读取附件2真实数据...\n');


loadRaw = ...
    readmatrix( ...
    dataFile, ...
    'Sheet','小区负载', ...
    'Range','B2:EO366');


pvRaw = ...
    readmatrix( ...
    dataFile, ...
    'Sheet','光伏发电实际功率', ...
    'Range','B2:EO366');


if ~isequal(size(loadRaw),[365,144])

    error('负荷数据不是365×144');

end


if ~isequal(size(pvRaw),[365,144])

    error('光伏数据不是365×144');

end


if any(isnan(loadRaw),'all') ...
        || ...
        any(isnan(pvRaw),'all')

    error('真实负荷或真实光伏中存在NaN');

end


%% ============================================================
% 5. 2月1日至12月31日
%% ============================================================

predDays = ...
    32:365;


nDay = ...
    length(predDays);


nTime = ...
    144;


predDates = ...
    ( ...
    datetime(2025,2,1): ...
    days(1): ...
    datetime(2025,12,31) ...
    )';


actualLoad = ...
    loadRaw(predDays,:);


actualPV = ...
    pvRaw(predDays,:);


%% ============================================================
% 6. 尺寸检查
%% ============================================================

if ~isequal(size(predLoad),[334,144])

    error( ...
        'AS-Ridge负荷预测尺寸错误');

end


if ~isequal(size(predPV),[334,144])

    error( ...
        'AS-Ridge光伏预测尺寸错误');

end


if ~isequal( ...
        size(predLoad), ...
        size(predPV), ...
        size(actualLoad), ...
        size(actualPV))

    error( ...
        '预测和真实数据尺寸不一致');

end


%% ============================================================
% 7. 读取电价
%% ============================================================

Tprice = ...
    readtable( ...
    priceFile, ...
    'VariableNamingRule','preserve');


priceRaw = ...
    Tprice{:,2};


priceRaw = ...
    priceRaw(:);


if length(priceRaw)~=144

    error( ...
        '附件1电价不是144个10min时段');

end


%% ============================================================
% 8. 时间轴
%
% 原始附件：
%
% 00:10
% 00:20
% ...
% 23:50
% 0:00(+1)
%
% 内部统一：
%
% 00:00
% 00:10
% ...
% 23:50
%% ============================================================

idx = ...
    [144,1:143];


price = ...
    [ ...
    priceRaw(end);
    priceRaw(1:end-1)
    ];


predLoadRun = ...
    predLoad(:,idx);


predPVRun = ...
    predPV(:,idx);


actualLoadRun = ...
    actualLoad(:,idx);


actualPVRun = ...
    actualPV(:,idx);


fprintf('====================================================\n');
fprintf(' AS-Ridge + AS-Ridge\n');
fprintf('====================================================\n');

fprintf('数据：%d天 × %d时段\n', ...
    nDay,nTime);

fprintf('历史窗口：%d天\n', ...
    ROLLING_WINDOW_DAYS);

fprintf('最少历史天数：%d天\n', ...
    MIN_HISTORY_DAYS);

fprintf('风险分位数：Q%.2f\n', ...
    Q_LEVEL);

fprintf('年末强制6000：%s\n', ...
    yesno(FORCE_FINAL_SOC_6000));

fprintf('允许同时充放电：是\n');

fprintf('写入result2：%s\n', ...
    yesno(WRITE_RESULT2));

fprintf('====================================================\n\n');


%% ============================================================
% 9. 原始净负荷
%% ============================================================

forecastNetLoad = ...
    predLoadRun ...
    -predPVRun;


realNetLoad = ...
    actualLoadRun ...
    -actualPVRun;


%% ============================================================
% 10. 净负荷历史残差
%
% residual =
%
% actual - forecast
%% ============================================================

residualNet = ...
    realNetLoad ...
    -forecastNetLoad;


%% ============================================================
% 11. 严格因果30日滚动Q0.8
%% ============================================================

q80Correction = ...
    zeros(nDay,nTime);


calibrationActive = ...
    false(nDay,1);


historyDaysUsed = ...
    zeros(nDay,1);


for d = 1:nDay


    histEnd = ...
        d-1;


    histStart = ...
        max( ...
        1, ...
        d-ROLLING_WINDOW_DAYS);


    if histEnd<histStart

        continue;

    end


    nHist = ...
        histEnd-histStart+1;


    historyDaysUsed(d) = ...
        nHist;


    if nHist<MIN_HISTORY_DAYS

        continue;

    end


    calibrationActive(d) = ...
        true;


    for t = 1:nTime


        r = ...
            residualNet( ...
            histStart:histEnd, ...
            t);


        r = ...
            r(isfinite(r));


        if length(r)>=MIN_HISTORY_DAYS

            q80Correction(d,t) = ...
                quantile( ...
                r, ...
                Q_LEVEL);

        end


    end


end


%% ============================================================
% 12. Q0.8风险校准
%% ============================================================

correctedNetLoad = ...
    forecastNetLoad ...
    +q80Correction;


%% PV预测保持AS-Ridge不动

correctedLoadRun = ...
    correctedNetLoad ...
    +predPVRun;


correctedLoadRun = ...
    max( ...
    correctedLoadRun, ...
    0);


%% ============================================================
% 13. Q0.8诊断
%% ============================================================

activeMatrix = ...
    repmat( ...
    calibrationActive, ...
    1,nTime);


qActive = ...
    q80Correction(activeMatrix);


if isempty(qActive)

    qMean = NaN;

    qMin = NaN;

    qMax = NaN;

else

    qMean = mean(qActive);

    qMin = min(qActive);

    qMax = max(qActive);

end


if any(activeMatrix,'all')


    rawErrorActive = ...
        forecastNetLoad(activeMatrix) ...
        -realNetLoad(activeMatrix);


    correctedErrorActive = ...
        correctedNetLoad(activeMatrix) ...
        -realNetLoad(activeMatrix);


    netBiasBefore = ...
        mean(rawErrorActive);


    netMAEBefore = ...
        mean(abs(rawErrorActive));


    netBiasAfter = ...
        mean(correctedErrorActive);


    netMAEAfter = ...
        mean(abs(correctedErrorActive));


else

    netBiasBefore = NaN;

    netMAEBefore = NaN;

    netBiasAfter = NaN;

    netMAEAfter = NaN;

end


fprintf('====================================================\n');
fprintf(' Q0.8风险校准\n');
fprintf('====================================================\n');

fprintf('启用校准：%d / %d天\n', ...
    sum(calibrationActive), ...
    nDay);


if any(calibrationActive)

    firstActive = ...
        find( ...
        calibrationActive, ...
        1, ...
        'first');


    fprintf('首次启用：%s\n', ...
        string(predDates(firstActive)));

end


fprintf('Q0.8平均：%.4f kW\n',qMean);

fprintf('Q0.8最小：%.4f kW\n',qMin);

fprintf('Q0.8最大：%.4f kW\n',qMax);

fprintf('\n');

fprintf('校准前Bias：%.4f kW\n', ...
    netBiasBefore);

fprintf('校准后Bias：%.4f kW\n', ...
    netBiasAfter);

fprintf('校准前MAE：%.4f kW\n', ...
    netMAEBefore);

fprintf('校准后MAE：%.4f kW\n', ...
    netMAEAfter);

fprintf('====================================================\n\n');


%% ============================================================
% 14. 储能参数
%% ============================================================

dt = ...
    10/60;


eta_ch = ...
    0.90;


eta_dis = ...
    0.90;


Ecapacity = ...
    12000;


Emin = ...
    1200;


Emax = ...
    10800;


Einitial = ...
    6000;


EfinalTarget = ...
    6000;


Pmax = ...
    5000;


Wmax = ...
    Pmax*dt;


%% ============================================================
% 15. LP参数
%
% 当前版本允许同时充放电
%% ============================================================

cyclePenalty = ...
    0;


curtailPenalty = ...
    1e-5;


%% ============================================================
% 16. LP设置
%% ============================================================

lpOptions = ...
    optimoptions( ...
    'linprog', ...
    'Algorithm','dual-simplex-highs', ...
    'Display','none');


%% ============================================================
% 17. 初始化
%% ============================================================

planGrid = ...
    zeros(nDay,nTime);


planCharge = ...
    zeros(nDay,nTime);


planDischarge = ...
    zeros(nDay,nTime);


planCurtail = ...
    zeros(nDay,nTime);


planSOCend = ...
    zeros(nDay,1);


actualCharge = ...
    zeros(nDay,nTime);


actualDischarge = ...
    zeros(nDay,nTime);


actualSpill = ...
    zeros(nDay,nTime);


emergencyGrid = ...
    zeros(nDay,nTime);


actualBplan = ...
    zeros(nDay,nTime);


actualB0 = ...
    zeros(nDay,nTime);


actualB = ...
    zeros(nDay,nTime);


actualSOC = ...
    zeros(nDay,nTime+1);


SOCstart = ...
    zeros(nDay,1);


SOCend = ...
    zeros(nDay,1);


terminalConstraintActive = ...
    false(nDay,nTime);


planCostDay = ...
    zeros(nDay,1);


emergencyCostDay = ...
    zeros(nDay,1);


totalCostDay = ...
    zeros(nDay,1);


%% ============================================================
% 18. 全年逐日运行
%% ============================================================

Ecurrent = ...
    Einitial;


timerMain = ...
    tic;


for d = 1:nDay


    currentDate = ...
        predDates(d);


    isLastDay = ...
        (d==nDay);


    if mod(d-1,20)==0 || isLastDay

        fprintf( ...
            '[%03d/%03d] %s  日初SOC=%.2f  Q80=%s\n', ...
            d, ...
            nDay, ...
            string(currentDate), ...
            Ecurrent, ...
            yesno(calibrationActive(d)));

    end


    %% 日初SOC

    EdayStart = ...
        Ecurrent;


    SOCstart(d) = ...
        EdayStart;


    %% 日末SOC

    if isLastDay ...
            && FORCE_FINAL_SOC_6000


        terminalLow = ...
            EfinalTarget;


        terminalHigh = ...
            EfinalTarget;


    else


        terminalLow = ...
            Emin;


        terminalHigh = ...
            Emax;


    end


    %% ========================================================
    % 预测值
    %% ========================================================

    loadForecast = ...
        correctedLoadRun(d,:)';


    pvForecast = ...
        predPVRun(d,:)';


    %% ========================================================
    % 0:00全天计划LP
    %% ========================================================

    plan = ...
        solveDailyPlanTerminalSOC( ...
        loadForecast, ...
        pvForecast, ...
        price, ...
        EdayStart, ...
        terminalLow, ...
        terminalHigh, ...
        dt, ...
        eta_ch, ...
        eta_dis, ...
        Emin, ...
        Emax, ...
        Wmax, ...
        cyclePenalty, ...
        curtailPenalty, ...
        lpOptions);


    planGrid(d,:) = ...
        plan.Wgrid';


    planCharge(d,:) = ...
        plan.Wch';


    planDischarge(d,:) = ...
        plan.Wdis';


    planCurtail(d,:) = ...
        plan.Wcut';


    planSOCend(d) = ...
        plan.E(end);


    planCostDay(d) = ...
        sum( ...
        price ...
        .*plan.Wgrid);


    %% ========================================================
    % 当前日真实数据
    %% ========================================================

    loadActual = ...
        actualLoadRun(d,:)';


    pvActual = ...
        actualPVRun(d,:)';


    %% ========================================================
    % 严格逐10min因果实际执行
    %% ========================================================

    replay = ...
        replayActualDayCausalAllowSimultaneous( ...
        loadActual, ...
        pvActual, ...
        plan.Wgrid, ...
        plan.Wch, ...
        plan.Wdis, ...
        EdayStart, ...
        dt, ...
        eta_ch, ...
        eta_dis, ...
        Emin, ...
        Emax, ...
        Wmax, ...
        isLastDay ...
            && FORCE_FINAL_SOC_6000, ...
        EfinalTarget);


    actualCharge(d,:) = ...
        replay.Wch';


    actualDischarge(d,:) = ...
        replay.Wdis';


    actualSpill(d,:) = ...
        replay.Wspill';


    emergencyGrid(d,:) = ...
        replay.Wem';


    actualBplan(d,:) = ...
        replay.Bplan';


    actualB0(d,:) = ...
        replay.B0';


    actualB(d,:) = ...
        replay.Bactual';


    actualSOC(d,:) = ...
        replay.E';


    terminalConstraintActive(d,:) = ...
        replay.terminalConstraintActive';


    %% 跨日SOC

    Ecurrent = ...
        replay.Eend;


    SOCend(d) = ...
        Ecurrent;


    %% 紧急购电费

    emergencyCostDay(d) = ...
        sum( ...
        5 ...
        .*price ...
        .*replay.Wem);


    %% 总成本

    totalCostDay(d) = ...
        planCostDay(d) ...
        +emergencyCostDay(d);


end


runtime = ...
    toc(timerMain);


%% ============================================================
% 19. SOC合法性
%% ============================================================

tolSOC = ...
    1e-5;


allSOC = ...
    actualSOC(:,2:end);


SOC_OK = ...
    all( ...
    allSOC>=Emin-tolSOC ...
    & ...
    allSOC<=Emax+tolSOC, ...
    'all');


if ~SOC_OK

    error( ...
        '实际运行SOC存在越界');

end


if FORCE_FINAL_SOC_6000


    finalSOC_OK = ...
        abs( ...
        SOCend(end) ...
        -EfinalTarget) ...
        <=1e-4;


else


    finalSOC_OK = ...
        SOCend(end)>=Emin-tolSOC ...
        && ...
        SOCend(end)<=Emax+tolSOC;


end


%% ============================================================
% 20. 全年统计
%% ============================================================

totalPlanEnergy = ...
    sum( ...
    planGrid, ...
    'all');


totalEmergencyEnergy = ...
    sum( ...
    emergencyGrid, ...
    'all');


totalPlanCost = ...
    sum(planCostDay);


totalEmergencyCost = ...
    sum(emergencyCostDay);


totalCost = ...
    totalPlanCost ...
    +totalEmergencyCost;


totalPlanCurtail = ...
    sum( ...
    planCurtail, ...
    'all');


totalActualSpill = ...
    sum( ...
    actualSpill, ...
    'all');


totalCharge = ...
    sum( ...
    actualCharge, ...
    'all');


totalDischarge = ...
    sum( ...
    actualDischarge, ...
    'all');


emergencyDays = ...
    sum( ...
    any( ...
    emergencyGrid>1e-8, ...
    2));


emergencySlots = ...
    nnz( ...
    emergencyGrid>1e-8);


meanSOCend = ...
    mean(SOCend);


minSOCend = ...
    min(SOCend);


maxSOCend = ...
    max(SOCend);


minSOCAll = ...
    min( ...
    allSOC, ...
    [], ...
    'all');


maxSOCAll = ...
    max( ...
    allSOC, ...
    [], ...
    'all');


meanSOCAll = ...
    mean( ...
    allSOC, ...
    'all');


%% ============================================================
% 21. 同时充放电统计
%% ============================================================

planSimultaneousMask = ...
    planCharge>1e-8 ...
    & ...
    planDischarge>1e-8;


actualSimultaneousMask = ...
    actualCharge>1e-8 ...
    & ...
    actualDischarge>1e-8;


nPlanSimultaneousCD = ...
    nnz(planSimultaneousMask);


nActualSimultaneousCD = ...
    nnz(actualSimultaneousMask);


simultaneousCD = ...
    actualCharge ...
    .*actualDischarge;


maxSimultaneousCD = ...
    max( ...
    simultaneousCD, ...
    [], ...
    'all');


%% ============================================================
% 22. 结果输出
%% ============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' 最终结果：AS-Ridge + AS-Ridge\n');
fprintf('====================================================\n');


fprintf('全年计划购电量：%.2f kWh\n', ...
    totalPlanEnergy);


fprintf('全年计划购电费：%.2f 元\n', ...
    totalPlanCost);


fprintf('\n');


fprintf('全年紧急购电量：%.2f kWh\n', ...
    totalEmergencyEnergy);


fprintf('全年紧急购电费：%.2f 元\n', ...
    totalEmergencyCost);


fprintf('\n');


fprintf('全年总成本：%.2f 元\n', ...
    totalCost);


fprintf('\n');


fprintf('全年计划弃光量：%.2f kWh\n', ...
    totalPlanCurtail);


fprintf('全年actualSpill：%.2f kWh\n', ...
    totalActualSpill);


fprintf('\n');


fprintf('全年实际充电量：%.2f kWh\n', ...
    totalCharge);


fprintf('全年实际放电量：%.2f kWh\n', ...
    totalDischarge);


fprintf('\n');


fprintf('紧急购电天数：%d 天\n', ...
    emergencyDays);


fprintf('紧急购电时段：%d 个\n', ...
    emergencySlots);


fprintf('\n');


fprintf('平均日末SOC：%.2f kWh\n', ...
    meanSOCend);


fprintf('最小日末SOC：%.2f kWh\n', ...
    minSOCend);


fprintf('最大日末SOC：%.2f kWh\n', ...
    maxSOCend);


fprintf('\n');


fprintf('全过程最低SOC：%.2f kWh\n', ...
    minSOCAll);


fprintf('全过程最高SOC：%.2f kWh\n', ...
    maxSOCAll);


fprintf('全过程平均SOC：%.2f kWh\n', ...
    meanSOCAll);


fprintf('\n');


fprintf('最终SOC：%.6f kWh\n', ...
    SOCend(end));


fprintf('全过程SOC合法：%s\n', ...
    yesno(SOC_OK));


fprintf('最终SOC合法：%s\n', ...
    yesno(finalSOC_OK));


fprintf('\n');


fprintf('计划同时充放电时段：%d\n', ...
    nPlanSimultaneousCD);


fprintf('实际同时充放电时段：%d\n', ...
    nActualSimultaneousCD);


fprintf('max(charge*discharge)：%.6e\n', ...
    maxSimultaneousCD);


fprintf('====================================================\n');


%% ============================================================
% 23. 与热力图AS-Ridge + AS-Ridge检查
%% ============================================================

heatmapReference = ...
    13952512;


fprintf('\n');
fprintf('====================================================\n');
fprintf(' 与16组合热力图一致性检查\n');
fprintf('====================================================\n');


fprintf('热力图AS-Ridge+AS-Ridge约：%.2f 元\n', ...
    heatmapReference);


fprintf('本程序总成本：%.2f 元\n', ...
    totalCost);


fprintf('差值：%+.2f 元\n', ...
    totalCost-heatmapReference);


fprintf('====================================================\n');


%% ============================================================
% 24. 紧急购电 / spill原因诊断
%% ============================================================

diagResult = ...
    diagnoseEmergencyAndSpill( ...
    emergencyGrid, ...
    actualSpill, ...
    actualCharge, ...
    actualDischarge, ...
    actualSOC, ...
    terminalConstraintActive, ...
    Emin, ...
    Emax, ...
    Wmax);


fprintf('\n');
fprintf('====================================================\n');
fprintf(' 紧急购电原因\n');
fprintf('====================================================\n');


fprintf('SOC下限受限：%d 时段，%.2f kWh\n', ...
    diagResult.emSOC_slots, ...
    diagResult.emSOC_energy);


fprintf('放电功率受限：%d 时段，%.2f kWh\n', ...
    diagResult.emPower_slots, ...
    diagResult.emPower_energy);


fprintf('SOC和功率同时受限：%d 时段，%.2f kWh\n', ...
    diagResult.emBoth_slots, ...
    diagResult.emBoth_energy);


fprintf('其他原因：%d 时段，%.2f kWh\n', ...
    diagResult.emOther_slots, ...
    diagResult.emOther_energy);


fprintf('====================================================\n');


%% ============================================================
% 25. 保存MAT
%% ============================================================

save( ...
    matFile, ...
    'predLoadRun', ...
    'predPVRun', ...
    'actualLoadRun', ...
    'actualPVRun', ...
    'forecastNetLoad', ...
    'realNetLoad', ...
    'residualNet', ...
    'q80Correction', ...
    'correctedNetLoad', ...
    'correctedLoadRun', ...
    'calibrationActive', ...
    'historyDaysUsed', ...
    'planGrid', ...
    'planCharge', ...
    'planDischarge', ...
    'planCurtail', ...
    'actualCharge', ...
    'actualDischarge', ...
    'actualSpill', ...
    'emergencyGrid', ...
    'actualSOC', ...
    'SOCstart', ...
    'SOCend', ...
    'planCostDay', ...
    'emergencyCostDay', ...
    'totalCostDay', ...
    'totalPlanEnergy', ...
    'totalEmergencyEnergy', ...
    'totalPlanCost', ...
    'totalEmergencyCost', ...
    'totalCost', ...
    'totalPlanCurtail', ...
    'totalActualSpill', ...
    'totalCharge', ...
    'totalDischarge', ...
    'emergencyDays', ...
    'emergencySlots', ...
    'nPlanSimultaneousCD', ...
    'nActualSimultaneousCD', ...
    'FORCE_FINAL_SOC_6000', ...
    'Q_LEVEL', ...
    'ROLLING_WINDOW_DAYS', ...
    'MIN_HISTORY_DAYS', ...
    '-v7.3');


fprintf('\nMAT已保存：\n%s\n', ...
    matFile);


%% ============================================================
% 26. ★正式写入result2.xlsx
%% ============================================================

if WRITE_RESULT2


    fprintf('\n');
    fprintf('====================================================\n');
    fprintf(' 正在写入官方result2.xlsx\n');
    fprintf('====================================================\n');


    %% ========================================================
    % 26.1 先备份原result2
    %% ========================================================

    timeStamp = ...
        datestr( ...
        now, ...
        'yyyymmdd_HHMMSS');


    backupFile = ...
        fullfile( ...
        baseDir, ...
        '附件5', ...
        ['result2_backup_' ...
        timeStamp ...
        '.xlsx']);


    [backupOK,backupMsg] = ...
        copyfile( ...
        resultFile, ...
        backupFile);


    if ~backupOK

        error( ...
            ['无法备份result2.xlsx。\n', ...
            '请确认Excel文件没有被占用。\n', ...
            '%s'], ...
            backupMsg);

    end


    fprintf('原result2已备份：\n%s\n\n', ...
        backupFile);


    %% ========================================================
    % 26.2 计划购电量
    %
    % 内部：
    % 00:00 00:10 ... 23:50
    %
    % 官方表：
    % 00:10 ... 23:50 0:00(+1)
    %% ========================================================

    planOut = ...
        [ ...
        planGrid(:,2:end), ...
        planGrid(:,1)
        ];


    writematrix( ...
        planOut, ...
        resultFile, ...
        'Sheet','计划购电量', ...
        'Range','B2');


    %% 每日计划购电总量

    writematrix( ...
        sum(planGrid,2), ...
        resultFile, ...
        'Sheet','计划购电量', ...
        'Range','EP2');


    %% 每日计划购电费

    writematrix( ...
        planCostDay, ...
        resultFile, ...
        'Sheet','计划购电量', ...
        'Range','EQ2');


    %% ========================================================
    % 26.3 充放电量
    %% ========================================================

    blockNames = {
        '0:00-4:00'
        '4:00-8:00'
        '8:00-12:00'
        '12:00-16:00'
        '16:00-20:00'
        '20:00-24:00'
        };


    chargeRows = ...
        cell( ...
        nDay*6+1, ...
        6);


    chargeRows(1,:) = {
        '日期'
        '时间段'
        '充电量'
        '放电量'
        '时刻'
        '储电量'
        };


    row = ...
        2;


    for d = 1:nDay


        for b = 1:6


            slots = ...
                (b-1)*24+1:b*24;


            if b==1

                chargeRows{row,1} = ...
                    datestr( ...
                    predDates(d), ...
                    'yyyy-mm-dd');

            else

                chargeRows{row,1} = ...
                    '';

            end


            chargeRows{row,2} = ...
                blockNames{b};


            chargeRows{row,3} = ...
                sum( ...
                actualCharge(d,slots));


            chargeRows{row,4} = ...
                sum( ...
                actualDischarge(d,slots));


            if b==1


                chargeRows{row,5} = ...
                    '0:00';


                chargeRows{row,6} = ...
                    SOCstart(d);


            elseif b==6


                chargeRows{row,5} = ...
                    '24:00';


                chargeRows{row,6} = ...
                    SOCend(d);


            else


                chargeRows{row,5} = ...
                    '';


                chargeRows{row,6} = ...
                    [];


            end


            row = ...
                row+1;


        end


    end


    %% 先清空旧内容

    blankCharge = ...
        repmat( ...
        {''}, ...
        nDay*6+5, ...
        6);


    writecell( ...
        blankCharge, ...
        resultFile, ...
        'Sheet','充放电量', ...
        'Range','A1');


    %% 写入正式数据

    writecell( ...
        chargeRows, ...
        resultFile, ...
        'Sheet','充放电量', ...
        'Range','A1');


    %% ========================================================
    % 26.4 紧急购电
    %% ========================================================

    emergencyRows = {
        '日期','购电时间段','购电量'
        };


    for d = 1:nDay


        em = ...
            emergencyGrid(d,:);


        active = ...
            em>1e-8;


        %% 当日无紧急购电

        if ~any(active)


            emergencyRows(end+1,:) = { ...
                datestr( ...
                predDates(d), ...
                'yyyy-mm-dd'), ...
                '', ...
                []};


            continue;

        end


        %% 连续紧急购电段

        diffActive = ...
            diff( ...
            [false active false]);


        startIdx = ...
            find( ...
            diffActive==1);


        endIdx = ...
            find( ...
            diffActive==-1)-1;


        for e = 1:length(startIdx)


            s = ...
                startIdx(e);


            f = ...
                endIdx(e);


            eventEnergy = ...
                sum( ...
                em(s:f));


            eventLabel = ...
                makeTimeRange( ...
                s,f);


            if e==1

                dateText = ...
                    datestr( ...
                    predDates(d), ...
                    'yyyy-mm-dd');

            else

                dateText = ...
                    '';

            end


            emergencyRows(end+1,:) = { ...
                dateText, ...
                eventLabel, ...
                eventEnergy};


        end


    end


    %% 清空旧紧急购电数据

    blankEmergency = ...
        repmat( ...
        {''}, ...
        5000, ...
        3);


    writecell( ...
        blankEmergency, ...
        resultFile, ...
        'Sheet','紧急购电量', ...
        'Range','A1');


    %% 写入新数据

    writecell( ...
        emergencyRows, ...
        resultFile, ...
        'Sheet','紧急购电量', ...
        'Range','A1');


    fprintf('\n');
    fprintf('====================================================\n');
    fprintf(' result2.xlsx写入成功\n');
    fprintf('====================================================\n');


    fprintf('正式结果：\n%s\n', ...
        resultFile);


    fprintf('\n备份文件：\n%s\n', ...
        backupFile);


end


fprintf('\n');
fprintf('====================================================\n');
fprintf(' 全部完成\n');
fprintf('====================================================\n');

fprintf('运行时间：%.2f min\n', ...
    runtime/60);

fprintf('总成本：%.2f 元\n', ...
    totalCost);

fprintf('====================================================\n');


%% ============================================================
% ============================================================
% 局部函数1：
%
% 日前计划LP
%
% 没有充放电互斥约束
%% ============================================================
%% ============================================================

function plan = solveDailyPlanTerminalSOC( ...
    Pload, ...
    Pv, ...
    price, ...
    Estart, ...
    terminalLow, ...
    terminalHigh, ...
    dt, ...
    eta_ch, ...
    eta_dis, ...
    Emin, ...
    Emax, ...
    Wmax, ...
    cyclePenalty, ...
    curtailPenalty, ...
    options)


N = ...
    length(price);


Wload = ...
    Pload(:)*dt;


Wpv = ...
    Pv(:)*dt;


price = ...
    price(:);


idxGrid = ...
    1:N;


idxCh = ...
    N+(1:N);


idxDis = ...
    2*N+(1:N);


idxCut = ...
    3*N+(1:N);


idxE = ...
    4*N+(1:N+1);


nvar = ...
    5*N+1;


%% ============================================================
% 目标
%% ============================================================

f = ...
    zeros(nvar,1);


f(idxGrid) = ...
    price;


f(idxCh) = ...
    cyclePenalty;


f(idxDis) = ...
    cyclePenalty;


f(idxCut) = ...
    curtailPenalty;


%% ============================================================
% 等式约束
%% ============================================================

Aeq = ...
    zeros( ...
    2*N+1, ...
    nvar);


beq = ...
    zeros( ...
    2*N+1, ...
    1);


%% 供需平衡

for t = 1:N


    Aeq(t,idxGrid(t)) = ...
        1;


    Aeq(t,idxCh(t)) = ...
        -1;


    Aeq(t,idxDis(t)) = ...
        1;


    Aeq(t,idxCut(t)) = ...
        -1;


    beq(t) = ...
        Wload(t) ...
        -Wpv(t);


end


%% SOC动态

for t = 1:N


    r = ...
        N+t;


    Aeq(r,idxE(t)) = ...
        -1;


    Aeq(r,idxE(t+1)) = ...
        1;


    Aeq(r,idxCh(t)) = ...
        -eta_ch;


    Aeq(r,idxDis(t)) = ...
        1/eta_dis;


end


%% 日初SOC

Aeq(2*N+1,idxE(1)) = ...
    1;


beq(2*N+1) = ...
    Estart;


%% ============================================================
% 上下界
%% ============================================================

lb = ...
    zeros(nvar,1);


ub = ...
    inf(nvar,1);


ub(idxCh) = ...
    Wmax;


ub(idxDis) = ...
    Wmax;


%% 没有充放电互斥约束


ub(idxCut) = ...
    Wpv;


lb(idxE) = ...
    Emin;


ub(idxE) = ...
    Emax;


lb(idxE(end)) = ...
    terminalLow;


ub(idxE(end)) = ...
    terminalHigh;


%% 求解

[x,~,exitflag] = ...
    linprog( ...
    f, ...
    [],[], ...
    Aeq, ...
    beq, ...
    lb, ...
    ub, ...
    options);


if exitflag<=0

    error( ...
        ['计划LP失败：', ...
        'Estart=%.2f，terminal=[%.2f,%.2f]'], ...
        Estart, ...
        terminalLow, ...
        terminalHigh);

end


plan.Wgrid = ...
    x(idxGrid);


plan.Wch = ...
    x(idxCh);


plan.Wdis = ...
    x(idxDis);


plan.Wcut = ...
    x(idxCut);


plan.E = ...
    x(idxE);


end


%% ============================================================
% ============================================================
% 局部函数2：
%
% 严格因果实际执行
%
% 允许同时充放电
%% ============================================================
%% ============================================================

function replay = replayActualDayCausalAllowSimultaneous( ...
    Pload, ...
    Pv, ...
    Wgrid, ...
    WchPlan, ...
    WdisPlan, ...
    Estart, ...
    dt, ...
    eta_ch, ...
    eta_dis, ...
    Emin, ...
    Emax, ...
    Wmax, ...
    forceFinalSOC, ...
    EfinalTarget)


N = ...
    length(Wgrid);


Wload = ...
    Pload(:)*dt;


Wpv = ...
    Pv(:)*dt;


Wgrid = ...
    Wgrid(:);


WchPlan = ...
    WchPlan(:);


WdisPlan = ...
    WdisPlan(:);


Wch = ...
    zeros(N,1);


Wdis = ...
    zeros(N,1);


Wspill = ...
    zeros(N,1);


Wem = ...
    zeros(N,1);


Bplan = ...
    zeros(N,1);


B0 = ...
    zeros(N,1);


Bactual = ...
    zeros(N,1);


E = ...
    zeros(N+1,1);


terminalConstraintActive = ...
    false(N,1);


E(1) = ...
    Estart;


for t = 1:N


    Ecurrent = ...
        E(t);


    %% ========================================================
    % 当前SOC允许范围
    %% ========================================================

    EnextLow = ...
        Emin;


    EnextHigh = ...
        Emax;


    %% ========================================================
    % 可选年末6000
    %% ========================================================

    if forceFinalSOC


        remainingSlots = ...
            N-t;


        EnextMinReach = ...
            EfinalTarget ...
            -remainingSlots ...
            *eta_ch ...
            *Wmax;


        EnextMaxReach = ...
            EfinalTarget ...
            +remainingSlots ...
            *Wmax/eta_dis;


        EnextLowNew = ...
            max( ...
            Emin, ...
            EnextMinReach);


        EnextHighNew = ...
            min( ...
            Emax, ...
            EnextMaxReach);


        if EnextLowNew>EnextHighNew+1e-7

            error( ...
                '终点SOC可达区间不可行');

        end


        if EnextLowNew>Emin+1e-7 ...
                || ...
                EnextHighNew<Emax-1e-7

            terminalConstraintActive(t) = ...
                true;

        end


        EnextLow = ...
            EnextLowNew;


        EnextHigh = ...
            EnextHighNew;


    end


    %% ========================================================
    % 日前计划
    %% ========================================================

    WchNow = ...
        min( ...
        max(WchPlan(t),0), ...
        Wmax);


    WdisNow = ...
        min( ...
        max(WdisPlan(t),0), ...
        Wmax);


    Bplan(t) = ...
        WdisPlan(t) ...
        -WchPlan(t);


    EnextCandidate = ...
        Ecurrent ...
        +eta_ch*WchNow ...
        -WdisNow/eta_dis;


    %% ========================================================
    % SOC过低
    %% ========================================================

    if EnextCandidate<EnextLow


        needIncreaseSOC = ...
            EnextLow ...
            -EnextCandidate;


        reduceDischarge = ...
            min( ...
            WdisNow, ...
            needIncreaseSOC*eta_dis);


        WdisNow = ...
            WdisNow ...
            -reduceDischarge;


        EnextCandidate = ...
            Ecurrent ...
            +eta_ch*WchNow ...
            -WdisNow/eta_dis;


        if EnextCandidate<EnextLow-1e-10


            addCharge = ...
                min( ...
                Wmax-WchNow, ...
                (EnextLow-EnextCandidate)/eta_ch);


            WchNow = ...
                WchNow ...
                +addCharge;


            EnextCandidate = ...
                Ecurrent ...
                +eta_ch*WchNow ...
                -WdisNow/eta_dis;


        end


    end


    %% ========================================================
    % SOC过高
    %% ========================================================

    if EnextCandidate>EnextHigh


        needDecreaseSOC = ...
            EnextCandidate ...
            -EnextHigh;


        reduceCharge = ...
            min( ...
            WchNow, ...
            needDecreaseSOC/eta_ch);


        WchNow = ...
            WchNow ...
            -reduceCharge;


        EnextCandidate = ...
            Ecurrent ...
            +eta_ch*WchNow ...
            -WdisNow/eta_dis;


        if EnextCandidate>EnextHigh+1e-10


            addDischarge = ...
                min( ...
                Wmax-WdisNow, ...
                (EnextCandidate-EnextHigh)*eta_dis);


            WdisNow = ...
                WdisNow ...
                +addDischarge;


            EnextCandidate = ...
                Ecurrent ...
                +eta_ch*WchNow ...
                -WdisNow/eta_dis;


        end


    end


    if EnextCandidate<EnextLow-1e-6 ...
            || ...
            EnextCandidate>EnextHigh+1e-6

        error( ...
            '计划动作SOC不可行：t=%d', ...
            t);

    end


    %% 计划净输出

    B0(t) = ...
        WdisNow ...
        -WchNow;


    %% ========================================================
    % 当前真实供需
    %% ========================================================

    residual = ...
        Wload(t) ...
        +WchNow ...
        -Wpv(t) ...
        -Wgrid(t) ...
        -WdisNow;


    %% ========================================================
    % 缺电
    %% ========================================================

    if residual>0


        %% 先减少充电

        maxReduceChargeSOC = ...
            max( ...
            (EnextCandidate-EnextLow) ...
            /eta_ch, ...
            0);


        reduceCharge = ...
            min( ...
            [ ...
            residual, ...
            WchNow, ...
            maxReduceChargeSOC ...
            ]);


        WchNow = ...
            WchNow ...
            -reduceCharge;


        residual = ...
            residual ...
            -reduceCharge;


        EnextCandidate = ...
            EnextCandidate ...
            -eta_ch*reduceCharge;


        %% 再增加放电

        if residual>1e-12


            maxExtraDischargeSOC = ...
                eta_dis ...
                *max( ...
                EnextCandidate-EnextLow, ...
                0);


            maxExtraDischarge = ...
                min( ...
                Wmax-WdisNow, ...
                maxExtraDischargeSOC);


            extraDischarge = ...
                min( ...
                residual, ...
                maxExtraDischarge);


            WdisNow = ...
                WdisNow ...
                +extraDischarge;


            residual = ...
                residual ...
                -extraDischarge;


            EnextCandidate = ...
                EnextCandidate ...
                -extraDischarge/eta_dis;


        end


        %% 剩余紧急购电

        Wem(t) = ...
            max( ...
            residual, ...
            0);


        Wspill(t) = ...
            0;


    %% ========================================================
    % 富余
    %% ========================================================

    elseif residual<0


        surplus = ...
            -residual;


        %% 先减少放电

        maxReduceDischargeSOC = ...
            eta_dis ...
            *max( ...
            EnextHigh-EnextCandidate, ...
            0);


        reduceDischarge = ...
            min( ...
            [ ...
            surplus, ...
            WdisNow, ...
            maxReduceDischargeSOC ...
            ]);


        WdisNow = ...
            WdisNow ...
            -reduceDischarge;


        surplus = ...
            surplus ...
            -reduceDischarge;


        EnextCandidate = ...
            EnextCandidate ...
            +reduceDischarge/eta_dis;


        %% 再增加充电

        if surplus>1e-12


            maxExtraChargeSOC = ...
                max( ...
                EnextHigh-EnextCandidate, ...
                0) ...
                /eta_ch;


            maxExtraCharge = ...
                min( ...
                Wmax-WchNow, ...
                maxExtraChargeSOC);


            extraCharge = ...
                min( ...
                surplus, ...
                maxExtraCharge);


            WchNow = ...
                WchNow ...
                +extraCharge;


            surplus = ...
                surplus ...
                -extraCharge;


            EnextCandidate = ...
                EnextCandidate ...
                +eta_ch*extraCharge;


        end


        %% 剩余未利用

        Wspill(t) = ...
            max( ...
            surplus, ...
            0);


        Wem(t) = ...
            0;


    else


        Wem(t) = ...
            0;


        Wspill(t) = ...
            0;


    end


    %% ========================================================
    % 保存
    %% ========================================================

    Wch(t) = ...
        WchNow;


    Wdis(t) = ...
        WdisNow;


    Bactual(t) = ...
        Wdis(t) ...
        -Wch(t);


    E(t+1) = ...
        Ecurrent ...
        +eta_ch*Wch(t) ...
        -Wdis(t)/eta_dis;


    %% 数值保护

    if abs(E(t+1)-Emin)<1e-9

        E(t+1) = ...
            Emin;

    end


    if abs(E(t+1)-Emax)<1e-9

        E(t+1) = ...
            Emax;

    end


    %% SOC检查

    if E(t+1)<Emin-1e-6 ...
            || ...
            E(t+1)>Emax+1e-6

        error( ...
            'SOC越界：t=%d', ...
            t);

    end


    %% 功率检查

    if Wch(t)<-1e-8 ...
            || ...
            Wch(t)>Wmax+1e-6

        error( ...
            '充电功率越界：t=%d', ...
            t);

    end


    if Wdis(t)<-1e-8 ...
            || ...
            Wdis(t)>Wmax+1e-6

        error( ...
            '放电功率越界：t=%d', ...
            t);

    end


    %% 供需平衡

    balanceError = ...
        Wgrid(t) ...
        +Wpv(t) ...
        +Wdis(t) ...
        +Wem(t) ...
        -Wload(t) ...
        -Wch(t) ...
        -Wspill(t);


    if abs(balanceError)>1e-5

        error( ...
            ['实际供需平衡失败：', ...
            't=%d,error=%.8f'], ...
            t, ...
            balanceError);

    end


end


if forceFinalSOC


    if abs( ...
            E(end)-EfinalTarget) ...
            >1e-4

        error( ...
            '最终SOC没有达到6000');

    end


end


replay.Wch = ...
    Wch;


replay.Wdis = ...
    Wdis;


replay.Wspill = ...
    Wspill;


replay.Wem = ...
    Wem;


replay.Bplan = ...
    Bplan;


replay.B0 = ...
    B0;


replay.Bactual = ...
    Bactual;


replay.E = ...
    E;


replay.Eend = ...
    E(end);


replay.terminalConstraintActive = ...
    terminalConstraintActive;


end


%% ============================================================
% 局部函数3：
% 紧急购电 / spill原因
%% ============================================================

function R = diagnoseEmergencyAndSpill( ...
    emergencyGrid, ...
    actualSpill, ...
    actualCharge, ...
    actualDischarge, ...
    actualSOC, ...
    terminalConstraintActive, ...
    Emin, ...
    Emax, ...
    Wmax)


socTol = ...
    1;


powerTol = ...
    1e-5;


eventTol = ...
    1e-7;


SOCafter = ...
    actualSOC(:,2:end);


%% 紧急购电

emMask = ...
    emergencyGrid>eventTol;


emSOC = ...
    emMask ...
    & ...
    SOCafter<=Emin+socTol ...
    & ...
    actualDischarge<Wmax-powerTol;


emPower = ...
    emMask ...
    & ...
    SOCafter>Emin+socTol ...
    & ...
    actualDischarge>=Wmax-powerTol;


emBoth = ...
    emMask ...
    & ...
    SOCafter<=Emin+socTol ...
    & ...
    actualDischarge>=Wmax-powerTol;


emOther = ...
    emMask ...
    & ...
    ~( ...
    emSOC ...
    |emPower ...
    |emBoth);


R.emSOC_slots = ...
    nnz(emSOC);


R.emPower_slots = ...
    nnz(emPower);


R.emBoth_slots = ...
    nnz(emBoth);


R.emOther_slots = ...
    nnz(emOther);


R.emSOC_energy = ...
    sum( ...
    emergencyGrid(emSOC));


R.emPower_energy = ...
    sum( ...
    emergencyGrid(emPower));


R.emBoth_energy = ...
    sum( ...
    emergencyGrid(emBoth));


R.emOther_energy = ...
    sum( ...
    emergencyGrid(emOther));


R.emOtherTerminalSlots = ...
    nnz( ...
    emOther ...
    &terminalConstraintActive);


R.emOtherNonTerminalSlots = ...
    nnz( ...
    emOther ...
    &~terminalConstraintActive);


%% spill

spillMask = ...
    actualSpill>eventTol;


spillSOC = ...
    spillMask ...
    & ...
    SOCafter>=Emax-socTol ...
    & ...
    actualCharge<Wmax-powerTol;


spillPower = ...
    spillMask ...
    & ...
    SOCafter<Emax-socTol ...
    & ...
    actualCharge>=Wmax-powerTol;


spillBoth = ...
    spillMask ...
    & ...
    SOCafter>=Emax-socTol ...
    & ...
    actualCharge>=Wmax-powerTol;


spillOther = ...
    spillMask ...
    & ...
    ~( ...
    spillSOC ...
    |spillPower ...
    |spillBoth);


R.spillSOC_slots = ...
    nnz(spillSOC);


R.spillPower_slots = ...
    nnz(spillPower);


R.spillBoth_slots = ...
    nnz(spillBoth);


R.spillOther_slots = ...
    nnz(spillOther);


R.spillSOC_energy = ...
    sum( ...
    actualSpill(spillSOC));


R.spillPower_energy = ...
    sum( ...
    actualSpill(spillPower));


R.spillBoth_energy = ...
    sum( ...
    actualSpill(spillBoth));


R.spillOther_energy = ...
    sum( ...
    actualSpill(spillOther));


R.spillOtherTerminalSlots = ...
    nnz( ...
    spillOther ...
    &terminalConstraintActive);


R.spillOtherNonTerminalSlots = ...
    nnz( ...
    spillOther ...
    &~terminalConstraintActive);


end


%% ============================================================
% 局部函数4：
% 连续紧急购电时间范围
%% ============================================================

function txt = makeTimeRange(s,f)


startMin = ...
    (s-1)*10;


endMin = ...
    f*10;


startHour = ...
    floor(startMin/60);


startMinute = ...
    mod(startMin,60);


endHour = ...
    floor(endMin/60);


endMinute = ...
    mod(endMin,60);


txt = ...
    sprintf( ...
    '%d:%02d-%d:%02d', ...
    startHour, ...
    startMinute, ...
    endHour, ...
    endMinute);


end


%% ============================================================
% 局部函数5：
% 是 / 否
%% ============================================================

function s = yesno(tf)


if tf

    s = ...
        '是';

else

    s = ...
        '否';

end


end