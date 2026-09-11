%% ============================================================
% 2026 C题 问题2 —— V2
%
% V2 =
%
% V1严格因果实际回放
% +
% 最近30日净负荷历史残差Q0.8校准
%
% ============================================================
%
% 预测模型不变：
%
%   负荷：QAR tau=0.8
%   光伏：AS-Ridge tau=0.2
%
% 不重新训练任何预测模型。
%
% ============================================================
%
% 净负荷定义：
%
% realNetLoad
%   = actualLoad - actualPV
%
% forecastNetLoad
%   = predLoad - predPV
%
% residualNet
%   = realNetLoad - forecastNetLoad
%
% 对第d天，只使用：
%
% d之前已经发生的最多30天残差
%
% 对每个10min时段t：
%
% q80(d,t)
%   = Q_0.8{residualNet(history,t)}
%
% correctedNetLoad
%   = forecastNetLoad + q80
%
% 为保持PV预测不变：
%
% correctedLoad
%   = correctedNetLoad + predPV
%
% correctedLoad >= 0
%
% ============================================================
%
% 注意：
%
% q=0.8来自正常购电和5倍紧急购电之间
% 的非对称经济风险关系。
%
% 这里将0.8作为“具有经济意义的风险分位数”，
% 不宣称它是含储能跨时段约束问题的严格解析最优值。
%
% ============================================================

clear;
clc;
close all;


%% ============================================================
% 0. 用户开关
%% ============================================================

% ------------------------------------------------------------
% 为了与V0/V1公平比较，
% 第一次运行建议保持true
% ------------------------------------------------------------

FORCE_FINAL_SOC_6000 = false;


% ------------------------------------------------------------
% warm-up：
%
% 至少有多少天历史后才启用Q0.8校准
%
% 推荐7天。
% ------------------------------------------------------------

MIN_HISTORY_DAYS = 7;


% ------------------------------------------------------------
% 滚动历史窗口
% ------------------------------------------------------------

ROLLING_WINDOW_DAYS = 30;


% ------------------------------------------------------------
% 净负荷残差分位数
% ------------------------------------------------------------

Q_LEVEL = 0.80;


% ------------------------------------------------------------
% 测试阶段建议false，
% 避免覆盖现在已经生成的官方result2。
%
% 确认V2最终采用后再改为true。
% ------------------------------------------------------------

WRITE_RESULT2 = false;


%% ============================================================
% 1. 路径
%% ============================================================

baseDir = ...
    'E:\数模\2026年正式比赛\CUMCM2026Problems\C题\附件';


predictionFile = ...
    fullfile( ...
    baseDir, ...
    'Q2_QAR_ASRidge_predictions.mat');


priceFile = ...
    fullfile( ...
    baseDir, ...
    '附件1.xlsx');


resultFile = ...
    fullfile( ...
    baseDir, ...
    '附件5', ...
    'result2.xlsx');


if FORCE_FINAL_SOC_6000

    matFile = ...
        fullfile( ...
        baseDir, ...
        'Q2_V2_CAUSAL_NETQ80_finalSOC6000.mat');

else

    matFile = ...
        fullfile( ...
        baseDir, ...
        'Q2_V2_CAUSAL_NETQ80_freeFinalSOC.mat');

end


compareExcel = ...
    fullfile( ...
    baseDir, ...
    'Q2_V0_V1_V2_compare.xlsx');


%% ============================================================
% 2. V0基准
%% ============================================================

V0_planEnergy = ...
    21395677.71;


V0_emergencyEnergy = ...
    174511.64;


V0_planCost = ...
    13087238.98;


V0_emergencyCost = ...
    659675.71;


V0_totalCost = ...
    13746914.68;


V0_planCurtail = ...
    326932.66;


V0_actualSpill = ...
    896454.73;


V0_charge = ...
    14392342.77;


V0_discharge = ...
    11657797.64;


V0_emergencyDays = ...
    152;


V0_emergencySlots = ...
    2202;


V0_meanSOCend = ...
    1971.75;


V0_minSOCend = ...
    1200;


V0_maxSOCend = ...
    6441.32;


V0_finalSOC = ...
    6000;


%% ============================================================
% 3. V1基准
%% ============================================================

V1_planEnergy = ...
    21395677.71;


V1_emergencyEnergy = ...
    166335.32;


V1_planCost = ...
    13087238.98;


V1_emergencyCost = ...
    919945.48;


V1_totalCost = ...
    14007184.45;


V1_planCurtail = ...
    326932.66;


V1_actualSpill = ...
    2417466.06;


V1_charge = ...
    6343986.66;


V1_discharge = ...
    5138629.19;


V1_emergencyDays = ...
    152;


V1_emergencySlots = ...
    1270;


V1_meanSOCend = ...
    1971.75;


V1_minSOCend = ...
    1200;


V1_maxSOCend = ...
    6441.32;


V1_finalSOC = ...
    6000;


%% ============================================================
% 4. 文件检查
%% ============================================================

if ~isfile(predictionFile)

    error( ...
        '找不到预测文件：\n%s', ...
        predictionFile);

end


if ~isfile(priceFile)

    error( ...
        '找不到附件1：\n%s', ...
        priceFile);

end


if WRITE_RESULT2 && ~isfile(resultFile)

    error( ...
        '找不到result2.xlsx：\n%s', ...
        resultFile);

end


%% ============================================================
% 5. 读取预测结果
%% ============================================================

S = ...
    load(predictionFile);


requiredVariables = {
    'predLoad'
    'predPV'
    'actualLoad'
    'actualPV'
    };


for i = 1:length(requiredVariables)

    if ~isfield(S,requiredVariables{i})

        error( ...
            '预测MAT缺少变量：%s', ...
            requiredVariables{i});

    end

end


predLoad = ...
    S.predLoad;


predPV = ...
    S.predPV;


actualLoad = ...
    S.actualLoad;


actualPV = ...
    S.actualPV;


if isfield(S,'predDates')

    predDates = ...
        S.predDates;

else

    predDates = ...
        ( ...
        datetime(2025,2,1): ...
        days(1): ...
        datetime(2025,12,31) ...
        )';

end


[nDay,nTime] = ...
    size(predLoad);


if nDay~=334 || nTime~=144

    error( ...
        '预测矩阵应为334×144，现在为%d×%d', ...
        nDay,nTime);

end


if ~isequal( ...
        size(predLoad), ...
        size(predPV), ...
        size(actualLoad), ...
        size(actualPV))

    error( ...
        '四个预测/真实矩阵尺寸不一致');

end


%% ============================================================
% 6. 读取电价
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
        '电价不是144个10min时段');

end


%% ============================================================
% 7. 时间轴
%
% !!! V2暂不修改时间轴 !!!
%
% 这是为了确保：
%
% V1 -> V2
%
% 唯一核心变化就是净负荷Q0.8校准。
%
% 当前继续沿用V0/V1：
%
% 原附件：
%
%   00:10 ... 23:50 00:00(+1)
%
% 内部：
%
%   00:00 00:10 ... 23:50
%
% 后续单独进行时间轴审计。
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
fprintf(' V2：因果回放 + 30日净负荷Q0.8校准\n');
fprintf('====================================================\n');

fprintf('数据：%d 天 × %d 时段\n', ...
    nDay,nTime);

fprintf('历史窗口：%d 天\n', ...
    ROLLING_WINDOW_DAYS);

fprintf('最少历史天数：%d 天\n', ...
    MIN_HISTORY_DAYS);

fprintf('分位数：Q%.2f\n', ...
    Q_LEVEL);

fprintf('强制年末6000：%s\n', ...
    yesno(FORCE_FINAL_SOC_6000));

fprintf('WRITE_RESULT2：%s\n\n', ...
    yesno(WRITE_RESULT2));


%% ============================================================
% 8. 原始净负荷
%% ============================================================

forecastNetLoad = ...
    predLoadRun ...
    - predPVRun;


realNetLoad = ...
    actualLoadRun ...
    - actualPVRun;


%% ============================================================
% 9. 历史净负荷预测残差
%
% residualNet > 0：
%
% 实际净负荷 > 预测净负荷
%
% 即原计划偏低。
%% ============================================================

residualNet = ...
    realNetLoad ...
    - forecastNetLoad;


%% ============================================================
% 10. 严格因果滚动Q0.8
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

        historyDaysUsed(d) = ...
            0;

        continue;

    end


    nHist = ...
        histEnd-histStart+1;


    historyDaysUsed(d) = ...
        nHist;


    %% --------------------------------------------------------
    % 历史不足时：
    %
    % 暂时不修正
    %% --------------------------------------------------------

    if nHist<MIN_HISTORY_DAYS

        continue;

    end


    calibrationActive(d) = ...
        true;


    %% --------------------------------------------------------
    % 对每一个10min时段分别计算历史Q0.8
    %% --------------------------------------------------------

    for t = 1:nTime


        histResidual = ...
            residualNet( ...
            histStart:histEnd, ...
            t);


        histResidual = ...
            histResidual( ...
            isfinite(histResidual));


        if length(histResidual) ...
                >=MIN_HISTORY_DAYS


            q80Correction(d,t) = ...
                quantile( ...
                histResidual, ...
                Q_LEVEL);


        else


            q80Correction(d,t) = ...
                0;


        end


    end


end


%% ============================================================
% 11. 修正净负荷
%% ============================================================

correctedNetLoad = ...
    forecastNetLoad ...
    + q80Correction;


%% ============================================================
% 12. 方案A：
%
% 保留原predPV
%
% correctedLoad
%
% = correctedNetLoad + predPV
%
% 不再次修改光伏。
%% ============================================================

correctedLoadRun = ...
    correctedNetLoad ...
    + predPVRun;


%% 物理保护

correctedLoadRun = ...
    max( ...
    correctedLoadRun, ...
    0);


%% ============================================================
% 13. 校准诊断
%% ============================================================

activeMatrix = ...
    repmat( ...
    calibrationActive, ...
    1, ...
    nTime);


qActive = ...
    q80Correction(activeMatrix);


if isempty(qActive)

    qMean = ...
        NaN;

    qMin = ...
        NaN;

    qMax = ...
        NaN;

else

    qMean = ...
        mean(qActive);

    qMin = ...
        min(qActive);

    qMax = ...
        max(qActive);

end


%% ------------------------------------------------------------
% 净负荷预测误差
%
% 这里Bias定义：
%
% Bias = mean(prediction - actual)
%
% Bias > 0：预测偏高
% Bias < 0：预测偏低
%% ------------------------------------------------------------

if any(activeMatrix,'all')


    rawErrorActive = ...
        forecastNetLoad(activeMatrix) ...
        - realNetLoad(activeMatrix);


    correctedErrorActive = ...
        correctedNetLoad(activeMatrix) ...
        - realNetLoad(activeMatrix);


    netBiasBefore = ...
        mean(rawErrorActive);


    netMAEBefore = ...
        mean(abs(rawErrorActive));


    netBiasAfter = ...
        mean(correctedErrorActive);


    netMAEAfter = ...
        mean(abs(correctedErrorActive));


else


    netBiasBefore = ...
        NaN;

    netMAEBefore = ...
        NaN;

    netBiasAfter = ...
        NaN;

    netMAEAfter = ...
        NaN;


end


fprintf('====================================================\n');
fprintf(' Q0.8校准诊断\n');
fprintf('====================================================\n');


fprintf('启用校准的天数：%d / %d\n', ...
    sum(calibrationActive), ...
    nDay);


if any(calibrationActive)

    firstActive = ...
        find( ...
        calibrationActive, ...
        1, ...
        'first');


    fprintf('首次启用日期：%s\n', ...
        string(predDates(firstActive)));

end


fprintf('\n');


fprintf('q80平均值：%.4f kW\n', ...
    qMean);

fprintf('q80最小值：%.4f kW\n', ...
    qMin);

fprintf('q80最大值：%.4f kW\n', ...
    qMax);


fprintf('\n');


fprintf('净负荷校准前Bias：%.4f kW\n', ...
    netBiasBefore);

fprintf('净负荷校准后Bias：%.4f kW\n', ...
    netBiasAfter);


fprintf('\n');


fprintf('净负荷校准前MAE：%.4f kW\n', ...
    netMAEBefore);

fprintf('净负荷校准后MAE：%.4f kW\n', ...
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
% 15. 计划LP微小择优项
%
% 为保证V1/V2可比，
% 此处暂时与V1保持完全一致。
%% ============================================================

cyclePenalty = ...
    1e-7;


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
% 17. 初始化结果
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
            '[%03d/%03d] %s  日初SOC=%.2f  q80Active=%s\n', ...
            d, ...
            nDay, ...
            string(currentDate), ...
            Ecurrent, ...
            yesno(calibrationActive(d)));

    end


    %% ========================================================
    % 日初SOC
    %% ========================================================

    EdayStart = ...
        Ecurrent;


    SOCstart(d) = ...
        EdayStart;


    %% ========================================================
    % 日末约束
    %% ========================================================

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
    % V2计划预测输入
    %
    % 负荷：
    % correctedLoad
    %
    % PV：
    % 原AS-Ridge predPV
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


    %% ========================================================
    % 正式计划购电费
    %% ========================================================

    planCostDay(d) = ...
        sum( ...
        price ...
        .* plan.Wgrid);


    %% ========================================================
    % 实际数据
    %% ========================================================

    loadActual = ...
        actualLoadRun(d,:)';


    pvActual = ...
        actualPVRun(d,:)';


    %% ========================================================
    % V1同款严格因果实际执行
    %% ========================================================

    replay = ...
        replayActualDayCausal( ...
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


    %% ========================================================
    % SOC跨日
    %% ========================================================

    Ecurrent = ...
        replay.Eend;


    SOCend(d) = ...
        Ecurrent;


    %% ========================================================
    % 紧急购电费
    %% ========================================================

    emergencyCostDay(d) = ...
        sum( ...
        5 ...
        .* price ...
        .* replay.Wem);


    %% ========================================================
    % 当天正式总成本
    %% ========================================================

    totalCostDay(d) = ...
        planCostDay(d) ...
        + emergencyCostDay(d);


end


runtime = ...
    toc(timerMain);


%% ============================================================
% 19. 全过程SOC检查
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
        'V2实际全过程SOC存在越界');

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
    sum( ...
    planCostDay);


totalEmergencyCost = ...
    sum( ...
    emergencyCostDay);


totalCost = ...
    totalPlanCost ...
    + totalEmergencyCost;


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
    min(allSOC,[],'all');


maxSOCAll = ...
    max(allSOC,[],'all');


meanSOCAll = ...
    mean(allSOC,'all');


%% ============================================================
% 21. 同时充放电检查
%% ============================================================

simultaneousCD = ...
    actualCharge ...
    .* actualDischarge;


nSimultaneousCD = ...
    nnz( ...
    simultaneousCD>1e-8);


maxSimultaneousCD = ...
    max( ...
    simultaneousCD, ...
    [], ...
    'all');


%% ============================================================
% 22. 紧急购电原因诊断
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


%% ============================================================
% 23. V2结果
%% ============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' V2：因果回放 + 净负荷Q0.8校准\n');
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


fprintf('最终SOC约束满足：%s\n', ...
    yesno(finalSOC_OK));


fprintf('\n');


fprintf('明显同时充放电时段：%d\n', ...
    nSimultaneousCD);


fprintf('max(charge*discharge)：%.6e\n', ...
    maxSimultaneousCD);


fprintf('====================================================\n');


%% ============================================================
% 24. V0 / V1 / V2比较表
%% ============================================================

Version = [
    "V0-perfect foresight"
    "V1-causal"
    "V2-causal+NetQ80"
    ];


PlanEnergy_kWh = [
    V0_planEnergy
    V1_planEnergy
    totalPlanEnergy
    ];


PlanCost_yuan = [
    V0_planCost
    V1_planCost
    totalPlanCost
    ];


EmergencyEnergy_kWh = [
    V0_emergencyEnergy
    V1_emergencyEnergy
    totalEmergencyEnergy
    ];


EmergencyCost_yuan = [
    V0_emergencyCost
    V1_emergencyCost
    totalEmergencyCost
    ];


TotalCost_yuan = [
    V0_totalCost
    V1_totalCost
    totalCost
    ];


PlanCurtail_kWh = [
    V0_planCurtail
    V1_planCurtail
    totalPlanCurtail
    ];


ActualSpill_kWh = [
    V0_actualSpill
    V1_actualSpill
    totalActualSpill
    ];


EmergencyDays = [
    V0_emergencyDays
    V1_emergencyDays
    emergencyDays
    ];


EmergencySlots = [
    V0_emergencySlots
    V1_emergencySlots
    emergencySlots
    ];


ActualCharge_kWh = [
    V0_charge
    V1_charge
    totalCharge
    ];


ActualDischarge_kWh = [
    V0_discharge
    V1_discharge
    totalDischarge
    ];


MeanSOCend_kWh = [
    V0_meanSOCend
    V1_meanSOCend
    meanSOCend
    ];


MinSOCend_kWh = [
    V0_minSOCend
    V1_minSOCend
    minSOCend
    ];


MaxSOCend_kWh = [
    V0_maxSOCend
    V1_maxSOCend
    maxSOCend
    ];


FinalSOC_kWh = [
    V0_finalSOC
    V1_finalSOC
    SOCend(end)
    ];


comparisonTable = ...
    table( ...
    Version, ...
    PlanEnergy_kWh, ...
    PlanCost_yuan, ...
    EmergencyEnergy_kWh, ...
    EmergencyCost_yuan, ...
    TotalCost_yuan, ...
    PlanCurtail_kWh, ...
    ActualSpill_kWh, ...
    EmergencyDays, ...
    EmergencySlots, ...
    ActualCharge_kWh, ...
    ActualDischarge_kWh, ...
    MeanSOCend_kWh, ...
    MinSOCend_kWh, ...
    MaxSOCend_kWh, ...
    FinalSOC_kWh);


fprintf('\n');
fprintf('====================================================\n');
fprintf(' V0 / V1 / V2 总体比较\n');
fprintf('====================================================\n');


disp(comparisonTable);


%% ============================================================
% 25. V2相对V0
%% ============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' V2 相对 V0\n');
fprintf('====================================================\n');


fprintf('总成本变化：%+.2f 元\n', ...
    totalCost-V0_totalCost);


fprintf('总成本变化率：%+.4f%%\n', ...
    100 ...
    * (totalCost-V0_totalCost) ...
    / V0_totalCost);


fprintf('计划购电量变化：%+.2f kWh\n', ...
    totalPlanEnergy-V0_planEnergy);


fprintf('计划购电费变化：%+.2f 元\n', ...
    totalPlanCost-V0_planCost);


fprintf('紧急购电量变化：%+.2f kWh\n', ...
    totalEmergencyEnergy-V0_emergencyEnergy);


fprintf('紧急购电费变化：%+.2f 元\n', ...
    totalEmergencyCost-V0_emergencyCost);


fprintf('actualSpill变化：%+.2f kWh\n', ...
    totalActualSpill-V0_actualSpill);


fprintf('====================================================\n');


%% ============================================================
% 26. V2相对V1
%% ============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' V2 相对 V1 —— 这是最重要的比较\n');
fprintf('====================================================\n');


fprintf('总成本变化：%+.2f 元\n', ...
    totalCost-V1_totalCost);


fprintf('总成本变化率：%+.4f%%\n', ...
    100 ...
    * (totalCost-V1_totalCost) ...
    / V1_totalCost);


fprintf('\n');


fprintf('计划购电量变化：%+.2f kWh\n', ...
    totalPlanEnergy-V1_planEnergy);


fprintf('计划购电费变化：%+.2f 元\n', ...
    totalPlanCost-V1_planCost);


fprintf('\n');


fprintf('紧急购电量变化：%+.2f kWh\n', ...
    totalEmergencyEnergy-V1_emergencyEnergy);


fprintf('紧急购电费变化：%+.2f 元\n', ...
    totalEmergencyCost-V1_emergencyCost);


fprintf('\n');


fprintf('计划弃光量变化：%+.2f kWh\n', ...
    totalPlanCurtail-V1_planCurtail);


fprintf('actualSpill变化：%+.2f kWh\n', ...
    totalActualSpill-V1_actualSpill);


fprintf('\n');


fprintf('实际充电量变化：%+.2f kWh\n', ...
    totalCharge-V1_charge);


fprintf('实际放电量变化：%+.2f kWh\n', ...
    totalDischarge-V1_discharge);


fprintf('====================================================\n');


%% ============================================================
% 27. 紧急购电原因
%% ============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' V2紧急购电原因诊断\n');
fprintf('====================================================\n');


fprintf('① SOC下限受限：\n');

fprintf('   %d 个时段\n', ...
    diagResult.emSOC_slots);

fprintf('   %.2f kWh\n\n', ...
    diagResult.emSOC_energy);


fprintf('② 最大放电功率受限：\n');

fprintf('   %d 个时段\n', ...
    diagResult.emPower_slots);

fprintf('   %.2f kWh\n\n', ...
    diagResult.emPower_energy);


fprintf('④ SOC与功率同时受限：\n');

fprintf('   %d 个时段\n', ...
    diagResult.emBoth_slots);

fprintf('   %.2f kWh\n\n', ...
    diagResult.emBoth_energy);


fprintf('③ 有SOC余量且功率未满却仍紧急购电：\n');

fprintf('   %d 个时段\n', ...
    diagResult.emOther_slots);

fprintf('   %.2f kWh\n', ...
    diagResult.emOther_energy);


fprintf('   年末约束导致：%d 个\n', ...
    diagResult.emOtherTerminalSlots);


fprintf('   非年末约束导致：%d 个\n', ...
    diagResult.emOtherNonTerminalSlots);


if diagResult.emOtherNonTerminalSlots>0

    fprintf('\n*** 警告：因果执行可能存在逻辑异常。\n');

end


%% ============================================================
% 28. actualSpill原因
%% ============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' V2 actualSpill原因诊断\n');
fprintf('====================================================\n');


fprintf('① SOC达到上限：\n');

fprintf('   %d 个时段\n', ...
    diagResult.spillSOC_slots);

fprintf('   %.2f kWh\n\n', ...
    diagResult.spillSOC_energy);


fprintf('② 最大充电功率受限：\n');

fprintf('   %d 个时段\n', ...
    diagResult.spillPower_slots);

fprintf('   %.2f kWh\n\n', ...
    diagResult.spillPower_energy);


fprintf('④ SOC与功率同时受限：\n');

fprintf('   %d 个时段\n', ...
    diagResult.spillBoth_slots);

fprintf('   %.2f kWh\n\n', ...
    diagResult.spillBoth_energy);


fprintf('③ SOC未满且充电功率未满仍spill：\n');

fprintf('   %d 个时段\n', ...
    diagResult.spillOther_slots);

fprintf('   %.2f kWh\n', ...
    diagResult.spillOther_energy);


fprintf('   年末约束导致：%d 个\n', ...
    diagResult.spillOtherTerminalSlots);


fprintf('   非年末约束导致：%d 个\n', ...
    diagResult.spillOtherNonTerminalSlots);


if diagResult.spillOtherNonTerminalSlots>0

    fprintf('\n*** 警告：actualSpill执行逻辑可能异常。\n');

end


%% ============================================================
% 29. 保存比较Excel
%% ============================================================

writetable( ...
    comparisonTable, ...
    compareExcel, ...
    'Sheet','V0_V1_V2');


calibrationTable = ...
    table( ...
    qMean, ...
    qMin, ...
    qMax, ...
    netBiasBefore, ...
    netBiasAfter, ...
    netMAEBefore, ...
    netMAEAfter);


writetable( ...
    calibrationTable, ...
    compareExcel, ...
    'Sheet','Q80诊断');


fprintf('\n比较表已保存：\n%s\n', ...
    compareExcel);


%% ============================================================
% 30. 图：每日平均Q0.8
%% ============================================================

dailyQ80 = ...
    mean( ...
    q80Correction, ...
    2);


figure( ...
    'Color','w');


plot( ...
    dailyQ80, ...
    'LineWidth',1.1);


yline( ...
    0, ...
    '--');


xlabel('天数');


ylabel('平均 q_{0.8} / kW');


title('V2每日净负荷残差Q0.8校准量');


grid on;


%% ============================================================
% 31. 图：V1/V2成本比较
%% ============================================================

figure( ...
    'Color','w');


bar( ...
    [ ...
    V0_totalCost
    V1_totalCost
    totalCost
    ]);


xticks(1:3);


xticklabels({
    'V0'
    'V1'
    'V2'
    });


ylabel('全年总成本 / 元');


title('问题2 V0 / V1 / V2 全年总成本');


grid on;


%% ============================================================
% 32. 图：每日紧急购电
%% ============================================================

figure( ...
    'Color','w');


plot( ...
    sum(emergencyGrid,2), ...
    'LineWidth',1.0);


xlabel('天数');


ylabel('紧急购电 / kWh');


title('V2每日紧急购电');


grid on;


%% ============================================================
% 33. 可选：写官方result2
%% ============================================================

if WRITE_RESULT2


    fprintf('\n正在写官方result2.xlsx...\n');


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


    writematrix( ...
        sum(planGrid,2), ...
        resultFile, ...
        'Sheet','计划购电量', ...
        'Range','EP2');


    writematrix( ...
        planCostDay, ...
        resultFile, ...
        'Sheet','计划购电量', ...
        'Range','EQ2');


    %% ========================================================
    % 充放电表
    %% ========================================================

    blankCharge = ...
        repmat( ...
        {''}, ...
        nDay*6, ...
        6);


    writecell( ...
        blankCharge, ...
        resultFile, ...
        'Sheet','充放电量', ...
        'Range','A2');


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


    writecell( ...
        chargeRows, ...
        resultFile, ...
        'Sheet','充放电量', ...
        'Range','A1');


    %% ========================================================
    % 紧急购电
    %% ========================================================

    blankEmergency = ...
        repmat( ...
        {''}, ...
        5000, ...
        3);


    writecell( ...
        blankEmergency, ...
        resultFile, ...
        'Sheet','紧急购电量', ...
        'Range','A2');


    emergencyRows = {
        '日期','购电时间段','购电量'
        };


    for d = 1:nDay


        em = ...
            emergencyGrid(d,:);


        active = ...
            em>1e-8;


        if ~any(active)

            emergencyRows(end+1,:) = { ...
                datestr( ...
                predDates(d), ...
                'yyyy-mm-dd'), ...
                '', ...
                []};

            continue;

        end


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


    writecell( ...
        emergencyRows, ...
        resultFile, ...
        'Sheet','紧急购电量', ...
        'Range','A1');


    fprintf('官方result2写入完成。\n');


end


%% ============================================================
% 34. 保存MAT
%% ============================================================

save( ...
    matFile, ...
    'FORCE_FINAL_SOC_6000', ...
    'MIN_HISTORY_DAYS', ...
    'ROLLING_WINDOW_DAYS', ...
    'Q_LEVEL', ...
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
    'qMean', ...
    'qMin', ...
    'qMax', ...
    'netBiasBefore', ...
    'netBiasAfter', ...
    'netMAEBefore', ...
    'netMAEAfter', ...
    'planGrid', ...
    'planCharge', ...
    'planDischarge', ...
    'planCurtail', ...
    'planSOCend', ...
    'actualCharge', ...
    'actualDischarge', ...
    'actualSpill', ...
    'emergencyGrid', ...
    'actualBplan', ...
    'actualB0', ...
    'actualB', ...
    'actualSOC', ...
    'terminalConstraintActive', ...
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
    'meanSOCend', ...
    'minSOCend', ...
    'maxSOCend', ...
    'minSOCAll', ...
    'maxSOCAll', ...
    'meanSOCAll', ...
    'comparisonTable', ...
    '-v7.3');


fprintf('\n');
fprintf('====================================================\n');

fprintf('V2 MAT已保存：\n%s\n', ...
    matFile);

fprintf('\n运行时间：%.2f min\n', ...
    runtime/60);

fprintf('====================================================\n');


%% ============================================================
% ============================================================
% 局部函数1：
%
% 计划购电LP
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


%% 目标函数

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


%% 等式约束

Aeq = ...
    zeros( ...
    2*N+1, ...
    nvar);


beq = ...
    zeros( ...
    2*N+1, ...
    1);


%% 电量平衡

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


%% 上下界

lb = ...
    zeros(nvar,1);


ub = ...
    inf(nvar,1);


ub(idxCh) = ...
    Wmax;


ub(idxDis) = ...
    Wmax;


%% 计划弃光不超过预测PV

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
    Aeq,beq, ...
    lb,ub, ...
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
% V1/V2共同使用的严格因果实际执行
%% ============================================================
%% ============================================================

function replay = replayActualDayCausal( ...
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
    % 当前物理能力
    %% ========================================================

    maxDischarge = ...
        min( ...
        Wmax, ...
        eta_dis ...
        * max(Ecurrent-Emin,0));


    maxCharge = ...
        min( ...
        Wmax, ...
        max(Emax-Ecurrent,0) ...
        / eta_ch);


    BminPhysical = ...
        -maxCharge;


    BmaxPhysical = ...
        maxDischarge;


    Bmin = ...
        BminPhysical;


    Bmax = ...
        BmaxPhysical;


    %% ========================================================
    % 年末6000可达性
    %
    % 不使用未来真实负荷/PV。
    %% ========================================================

    if forceFinalSOC


        remainingSlots = ...
            N-t;


        EnextMinReach = ...
            EfinalTarget ...
            - remainingSlots ...
            * eta_ch ...
            * Wmax;


        EnextMaxReach = ...
            EfinalTarget ...
            + remainingSlots ...
            * Wmax/eta_dis;


        EnextMinReach = ...
            max( ...
            Emin, ...
            EnextMinReach);


        EnextMaxReach = ...
            min( ...
            Emax, ...
            EnextMaxReach);


        B_lower_terminal = ...
            batteryOutputForTargetSOC( ...
            Ecurrent, ...
            EnextMaxReach, ...
            eta_ch, ...
            eta_dis);


        B_upper_terminal = ...
            batteryOutputForTargetSOC( ...
            Ecurrent, ...
            EnextMinReach, ...
            eta_ch, ...
            eta_dis);


        oldBmin = ...
            Bmin;


        oldBmax = ...
            Bmax;


        Bmin = ...
            max( ...
            Bmin, ...
            B_lower_terminal);


        Bmax = ...
            min( ...
            Bmax, ...
            B_upper_terminal);


        if Bmin>Bmax+1e-7

            error( ...
                ['终点可达约束不可行：', ...
                't=%d,E=%.6f,Bmin=%.6f,Bmax=%.6f'], ...
                t, ...
                Ecurrent, ...
                Bmin, ...
                Bmax);

        end


        if Bmin>oldBmin+1e-7 ...
                || ...
                Bmax<oldBmax-1e-7

            terminalConstraintActive(t) = ...
                true;

        end


    end


    %% 日前计划净输出

    Bplan(t) = ...
        WdisPlan(t) ...
        -WchPlan(t);


    %% 先尽量执行日前储能计划

    B0(t) = ...
        min( ...
        max( ...
        Bplan(t), ...
        Bmin), ...
        Bmax);


    %% 当前真实供需差

    residual = ...
        Wload(t) ...
        -Wpv(t) ...
        -Wgrid(t) ...
        -B0(t);


    %% 缺电

    if residual>0


        extraDischarge = ...
            min( ...
            residual, ...
            Bmax-B0(t));


        Bactual(t) = ...
            B0(t) ...
            +extraDischarge;


        Wem(t) = ...
            residual ...
            -extraDischarge;


        Wspill(t) = ...
            0;


    %% 富余

    elseif residual<0


        extraAbsorb = ...
            min( ...
            -residual, ...
            B0(t)-Bmin);


        Bactual(t) = ...
            B0(t) ...
            -extraAbsorb;


        Wspill(t) = ...
            -residual ...
            -extraAbsorb;


        Wem(t) = ...
            0;


    else


        Bactual(t) = ...
            B0(t);


        Wem(t) = ...
            0;


        Wspill(t) = ...
            0;


    end


    %% ========================================================
    % 拆分充放电
    %% ========================================================

    if Bactual(t)>=0


        Wdis(t) = ...
            Bactual(t);


        Wch(t) = ...
            0;


        E(t+1) = ...
            Ecurrent ...
            -Wdis(t)/eta_dis;


    else


        Wdis(t) = ...
            0;


        Wch(t) = ...
            -Bactual(t);


        E(t+1) = ...
            Ecurrent ...
            +eta_ch*Wch(t);


    end


    %% ========================================================
    % 安全检查
    %% ========================================================

    if E(t+1)<Emin-1e-6 ...
            || ...
            E(t+1)>Emax+1e-6

        error( ...
            ['SOC越界：', ...
            't=%d,Ebefore=%.6f,Eafter=%.6f'], ...
            t, ...
            Ecurrent, ...
            E(t+1));

    end


    if Wch(t)>Wmax+1e-6 ...
            || ...
            Wdis(t)>Wmax+1e-6

        error( ...
            '充放电功率越界：t=%d', ...
            t);

    end


    if Wch(t)>1e-8 ...
            && ...
            Wdis(t)>1e-8

        error( ...
            '同时充放电：t=%d', ...
            t);

    end


    if abs(E(t+1)-Emin)<1e-9

        E(t+1) = ...
            Emin;

    end


    if abs(E(t+1)-Emax)<1e-9

        E(t+1) = ...
            Emax;

    end


end


if forceFinalSOC


    if abs( ...
            E(end)-EfinalTarget) ...
            >1e-4

        error( ...
            '最终SOC没有达到6000：%.6f', ...
            E(end));

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
% SOC目标 -> 电池净输出
%% ============================================================

function B = batteryOutputForTargetSOC( ...
    Ecurrent, ...
    Etarget, ...
    eta_ch, ...
    eta_dis)


if Etarget>=Ecurrent


    B = ...
        -(Etarget-Ecurrent) ...
        /eta_ch;


else


    B = ...
        eta_dis ...
        *(Ecurrent-Etarget);


end


end


%% ============================================================
% 局部函数4：
%
% 紧急购电 / actualSpill诊断
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


%% ============================================================
% 紧急购电
%% ============================================================

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


%% ============================================================
% spill
%% ============================================================

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
% 局部函数5：
% 连续紧急购电时间段
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
% 局部函数6：是/否
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