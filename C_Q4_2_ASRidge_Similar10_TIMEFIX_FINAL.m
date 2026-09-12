%% ============================================================
% 2026 C题 问题4-2 最终版
%
% 波动实时电价下重新计算问题2
%
% 最终问题2模型：
%
% AS-Ridge
% + Similar10
% + Causal Affine Recourse
%
% ============================================================
%
% 本程序不再：
%
% 1. 不再运行4×4=16种组合
% 2. 不再重新训练预测模型
% 3. 不再使用Q0.8风险校准
%
% ============================================================
%
% 与问题2相比，只改变电价：
%
% 日前计划：
%     使用严格因果“预测实时电价”
%
% 最终结算：
%     普通计划购电 × 附件4真实实时电价
%
% 紧急购电：
%     5 × 附件4真实实时电价
%
% ============================================================
%
% 实时电价预测：
%
% kL = 1
% 最近1个同星期日 → 预测日均价
%
% kS = 2
% 最近2个同星期日 → 预测日内相对形状
%
% 预测价格 =
% 预测日均价 × 预测相对形状
%
% ============================================================
%
% TIMEFIX：
%
% 原始144列保持不变
%
% col1   = 00:10，对应区间 00:00-00:10
% col36  = 06:00
% col37  = 06:10
% col72  = 12:00
% col73  = 12:10
% col108 = 18:00
% col109 = 18:10
% col144 = 次日00:00，对应23:50-24:00
%
% 不使用 [144,1:143]
%
% ============================================================

clear;
clc;
close all;

rng(20260912,'twister');


fprintf('====================================================\n');
fprintf(' C题问题4-2\n');
fprintf(' AS-Ridge + Similar10 + Causal Affine\n');
fprintf(' 波动实时电价 TIMEFIX\n');
fprintf('====================================================\n\n');


%% ============================================================
% 1. 路径
%% ============================================================

baseDir = ...
    'E:\数模\2026年正式比赛\CUMCM2026Problems\C题\附件';


%% 问题2最终MAT
Q2File = ...
    fullfile( ...
    baseDir, ...
    'Q2_P2_SIMILAR10_RESULT2_FINAL.mat');


%% 附件2
actualFile = ...
    fullfile( ...
    baseDir, ...
    '附件2.xlsx');


%% 附件4实时电价
price4File = ...
    fullfile( ...
    baseDir, ...
    '附件4.xlsx');


%% 官方result4-2
result4File = ...
    fullfile( ...
    baseDir, ...
    '附件5', ...
    'result4-2.xlsx');


%% 自己保存的完整MAT
resultMatFile = ...
    fullfile( ...
    baseDir, ...
    'Q4_2_ASRidge_Similar10_TIMEFIX_FINAL.mat');


%% 自己保存的分析Excel
resultExcelFile = ...
    fullfile( ...
    baseDir, ...
    'Q4_2_ASRidge_Similar10_TIMEFIX_ANALYSIS.xlsx');


%% SOC图
figSOCFile = ...
    fullfile( ...
    baseDir, ...
    'Q4_2_ASRidge_Similar10_SOC.png');


%% 实时电价预测示例
figPriceFile = ...
    fullfile( ...
    baseDir, ...
    'Q4_2_实时电价预测示例.png');


filesNeed = {
    Q2File
    actualFile
    price4File
    result4File
    };


for i = 1:length(filesNeed)

    if ~isfile(filesNeed{i})

        error( ...
            '找不到文件：\n%s', ...
            filesNeed{i});

    end

end


fprintf('数据目录：\n%s\n\n',baseDir);


%% ============================================================
% 2. 参数
%% ============================================================

cfg.dt = ...
    1/6;


cfg.etaCh = ...
    0.90;


cfg.etaDis = ...
    0.90;


cfg.Emin = ...
    1200;


cfg.Emax = ...
    10800;


cfg.Einitial = ...
    6000;


cfg.Wmax = ...
    5000/6;


cfg.emergencyFactor = ...
    5;


%% ------------------------------------------------------------
% Similar10参数
%% ------------------------------------------------------------

cfg.historyWindowDays = ...
    30;


cfg.minHistoryDays = ...
    7;


cfg.similarDayCount = ...
    10;


%% ------------------------------------------------------------
% 极小吞吐惩罚
%
% 不是实际储能费用，只作tie-break
%% ------------------------------------------------------------

cfg.cyclePenalty = ...
    1e-5;


%% ============================================================
% 3. 实时电价预测参数
%% ============================================================

PRICE_KL = ...
    1;


PRICE_KS = ...
    2;


%% ============================================================
% 4. 日期
%% ============================================================

datesAll = ...
    ( ...
    datetime(2025,1,1): ...
    days(1): ...
    datetime(2025,12,31) ...
    )';


targetDays = ...
    32:365;


predDatesDefault = ...
    datesAll(targetDays);


nDay = ...
    length(targetDays);


nTime = ...
    144;


if nDay~=334

    error('目标日期必须为334天。');

end


%% ============================================================
% 5. 读取问题2最终结果
%% ============================================================

fprintf('读取问题2最终MAT...\n');


Q2 = ...
    load(Q2File);


if ~isfield(Q2,'predLoad')

    error( ...
        'Q2 MAT中缺少 predLoad。');

end


if ~isfield(Q2,'predPV')

    error( ...
        'Q2 MAT中缺少 predPV。');

end


predLoad = ...
    Q2.predLoad;


predPV = ...
    Q2.predPV;


if ~isequal(size(predLoad),[334,144])

    error( ...
        'Q2 predLoad必须为334×144。');

end


if ~isequal(size(predPV),[334,144])

    error( ...
        'Q2 predPV必须为334×144。');

end


predLoad = ...
    max(predLoad,0);


predPV = ...
    max(predPV,0);


%% ------------------------------------------------------------
% 日期
%% ------------------------------------------------------------

if isfield(Q2,'predDates')

    predDates = ...
        Q2.predDates(:);

else

    predDates = ...
        predDatesDefault;

end


if length(predDates)~=334

    error( ...
        'predDates必须为334天。');

end


fprintf('问题2预测读取成功。\n');
fprintf('负载模型：AS-Ridge\n');
fprintf('光伏模型：AS-Ridge\n');
fprintf('调度模型：Similar10 + Causal Affine\n\n');


%% ============================================================
% 6. 读取真实负载和光伏
%
% 优先从问题2 MAT读取
%% ============================================================

if isfield(Q2,'actualLoad') ...
        &&isfield(Q2,'actualPV') ...
        &&isequal(size(Q2.actualLoad),[334,144]) ...
        &&isequal(size(Q2.actualPV),[334,144])

    actualLoad = ...
        Q2.actualLoad;


    actualPV = ...
        Q2.actualPV;


    fprintf('真实负载/PV直接读取Q2 MAT。\n\n');


else

    fprintf('Q2 MAT没有完整真实数据，读取附件2...\n');


    loadRaw = ...
        readmatrix( ...
        actualFile, ...
        'Sheet','小区负载', ...
        'Range','B2:EO366');


    pvRaw = ...
        readmatrix( ...
        actualFile, ...
        'Sheet','光伏发电实际功率', ...
        'Range','B2:EO366');


    if ~isequal(size(loadRaw),[365,144])

        error( ...
            '附件2负载必须为365×144。');

    end


    if ~isequal(size(pvRaw),[365,144])

        error( ...
            '附件2PV必须为365×144。');

    end


    actualLoad = ...
        loadRaw(targetDays,:);


    actualPV = ...
        pvRaw(targetDays,:);

end


if any(~isfinite(actualLoad),'all') ...
        ||any(~isfinite(actualPV),'all')

    error( ...
        '实际负载/PV存在NaN或非法值。');

end


%% ============================================================
% 7. 预测净负荷与真实残差
%% ============================================================

forecastNet = ...
    predLoad ...
    -predPV;


actualNet = ...
    actualLoad ...
    -actualPV;


residualNet = ...
    actualNet ...
    -forecastNet;


%% ============================================================
% 8. 读取附件4真实实时电价
%% ============================================================

fprintf('读取附件4实时电价...\n');


priceSheets = ...
    sheetnames(price4File);


priceAll = ...
    readmatrix( ...
    price4File, ...
    'Sheet',priceSheets(1), ...
    'Range','B2:EO366');


if ~isequal(size(priceAll),[365,144])

    error( ...
        '附件4实时电价必须为365×144。');

end


if any(~isfinite(priceAll),'all') ...
        ||any(priceAll<0,'all')

    error( ...
        '附件4存在非法实时电价。');

end


%% ------------------------------------------------------------
% 最终实际结算价格
%% ------------------------------------------------------------

actualPrice = ...
    priceAll(targetDays,:);


fprintf('附件4读取完成。\n\n');


%% ============================================================
% 9. 严格因果预测每天实时电价
%
% 只使用目标日期之前已经发生的价格
%% ============================================================

fprintf('生成严格因果实时电价预测...\n');


priceForecast = ...
    nan(nDay,nTime);


for kd = 1:nDay

    dFull = ...
        targetDays(kd);


    targetWD = ...
        weekday( ...
        datesAll(dFull));


    %% --------------------------------------------------------
    % 只能使用dFull之前
    %% --------------------------------------------------------

    histDays = ...
        1:(dFull-1);


    histWD = ...
        arrayfun( ...
        @(x) ...
        weekday(datesAll(x)), ...
        histDays);


    sameDays = ...
        histDays( ...
        histWD==targetWD);


    if length(sameDays)<max(PRICE_KL,PRICE_KS)

        error( ...
            '%s之前同星期历史不足。', ...
            string(datesAll(dFull)));

    end


    %% ========================================================
    % 9.1 日均价格
    %
    % 最近kL个同星期日
    %% ========================================================

    meanDays = ...
        sameDays( ...
        end-PRICE_KL+1:end);


    predDailyMean = ...
        mean( ...
        mean( ...
        priceAll(meanDays,:), ...
        2));


    %% ========================================================
    % 9.2 日内相对形状
    %
    % 最近kS个同星期日
    %% ========================================================

    shapeDays = ...
        sameDays( ...
        end-PRICE_KS+1:end);


    shapeMatrix = ...
        zeros( ...
        PRICE_KS, ...
        nTime);


    for k = 1:PRICE_KS

        onePrice = ...
            priceAll( ...
            shapeDays(k), ...
            :);


        oneMean = ...
            mean(onePrice);


        if oneMean<=1e-12

            oneMean = ...
                1;

        end


        shapeMatrix(k,:) = ...
            onePrice ...
            /oneMean;

    end


    predShape = ...
        mean( ...
        shapeMatrix, ...
        1);


    %% ========================================================
    % 9.3 最终实时价格预测
    %% ========================================================

    priceForecast(kd,:) = ...
        max( ...
        predDailyMean ...
        .*predShape, ...
        0);

end


%% ============================================================
% 10. 电价预测精度
%% ============================================================

priceError = ...
    priceForecast ...
    -actualPrice;


priceMAE = ...
    mean( ...
    abs(priceError), ...
    'all');


priceRMSE = ...
    sqrt( ...
    mean( ...
    priceError.^2, ...
    'all'));


priceBias = ...
    mean( ...
    priceError, ...
    'all');


fprintf('====================================================\n');
fprintf(' 实时电价预测\n');
fprintf('====================================================\n');


fprintf( ...
    'kL = %d\n', ...
    PRICE_KL);


fprintf( ...
    'kS = %d\n', ...
    PRICE_KS);


fprintf( ...
    'MAE = %.6f 元/kWh\n', ...
    priceMAE);


fprintf( ...
    'RMSE = %.6f 元/kWh\n', ...
    priceRMSE);


fprintf( ...
    'Bias = %+.6f 元/kWh\n', ...
    priceBias);


fprintf('====================================================\n\n');


%% ============================================================
% 11. LP
%% ============================================================

lpOptions = ...
    optimoptions( ...
    'linprog', ...
    'Algorithm','dual-simplex-highs', ...
    'Display','none');


%% ============================================================
% 12. 初始化
%% ============================================================

planGrid = ...
    zeros(nDay,nTime);


planChargeBase = ...
    zeros(nDay,nTime);


planDischargeBase = ...
    zeros(nDay,nTime);


planSOCBase = ...
    zeros(nDay,nTime+1);


actualCharge = ...
    zeros(nDay,nTime);


actualDischarge = ...
    zeros(nDay,nTime);


actualSpill = ...
    zeros(nDay,nTime);


emergencyGrid = ...
    zeros(nDay,nTime);


actualSOC = ...
    zeros(nDay,nTime+1);


SOCstart = ...
    zeros(nDay,1);


SOCend = ...
    zeros(nDay,1);


scenarioCount = ...
    zeros(nDay,1);


meanSimilarDistance = ...
    nan(nDay,1);


%% 优化时认为的购电费
predictedPlanCostDay = ...
    zeros(nDay,1);


%% 按附件4真实价格结算的购电费
actualPlanCostDay = ...
    zeros(nDay,1);


%% 紧急购电费
emergencyCostDay = ...
    zeros(nDay,1);


%% 总费用
totalCostDay = ...
    zeros(nDay,1);


%% ============================================================
% 13. 全年逐日运行
%% ============================================================

fprintf('====================================================\n');
fprintf(' 开始Q4-2全年调度\n');
fprintf('====================================================\n\n');


Ecurrent = ...
    cfg.Einitial;


timerDispatch = ...
    tic;


for d = 1:nDay

    SOCstart(d) = ...
        Ecurrent;


    %% ========================================================
    % 13.1 Similar10候选历史
    %% ========================================================

    histStart = ...
        max( ...
        1, ...
        d-cfg.historyWindowDays);


    histEnd = ...
        d-1;


    nHistory = ...
        histEnd-histStart+1;


    if nHistory>=cfg.minHistoryDays

        candidateDays = ...
            (histStart:histEnd)';


        %% ----------------------------------------------------
        % 当前负载预测尺度
        %% ----------------------------------------------------

        loadScale = ...
            max( ...
            mean( ...
            abs(predLoad(d,:))), ...
            1);


        %% ----------------------------------------------------
        % 当前PV预测尺度
        %% ----------------------------------------------------

        pvScale = ...
            max( ...
            mean( ...
            abs(predPV(d,:))), ...
            1);


        %% ----------------------------------------------------
        % 负载预测曲线距离
        %% ----------------------------------------------------

        loadDistance = ...
            sqrt( ...
            mean( ...
            ( ...
            ( ...
            predLoad(candidateDays,:) ...
            -predLoad(d,:) ...
            ) ...
            /loadScale ...
            ).^2, ...
            2));


        %% ----------------------------------------------------
        % PV预测曲线距离
        %% ----------------------------------------------------

        pvDistance = ...
            sqrt( ...
            mean( ...
            ( ...
            ( ...
            predPV(candidateDays,:) ...
            -predPV(d,:) ...
            ) ...
            /pvScale ...
            ).^2, ...
            2));


        %% ----------------------------------------------------
        % 综合相似度
        %% ----------------------------------------------------

        totalDistance = ...
            loadDistance ...
            +pvDistance;


        [~,order] = ...
            sort( ...
            totalDistance, ...
            'ascend');


        keepN = ...
            min( ...
            cfg.similarDayCount, ...
            numel(order));


        keep = ...
            order(1:keepN);


        selectedDays = ...
            candidateDays(keep);


        %% ----------------------------------------------------
        % 直接使用真实净负荷残差路径
        %% ----------------------------------------------------

        residualScenarios = ...
            residualNet( ...
            selectedDays, ...
            :);


        scenarioCount(d) = ...
            keepN;


        meanSimilarDistance(d) = ...
            mean( ...
            totalDistance(keep));


    else

        %% ----------------------------------------------------
        % 历史不足
        %% ----------------------------------------------------

        residualScenarios = ...
            zeros(1,nTime);


        scenarioCount(d) = ...
            1;


        meanSimilarDistance(d) = ...
            NaN;

    end


    %% ========================================================
    % 13.2 今天的预测实时电价
    %
    % ★优化只看到预测价格
    %% ========================================================

    predictedPriceDay = ...
        priceForecast(d,:)';


    %% ========================================================
    % 13.3 今天附件4真实电价
    %
    % ★仅用于最终结算
    %% ========================================================

    actualPriceDay = ...
        actualPrice(d,:)';


    %% ========================================================
    % 13.4 Similar10 causal affine计划
    %% ========================================================

    plan = ...
        solveCausalAffinePlan( ...
        forecastNet(d,:), ...
        residualScenarios, ...
        predictedPriceDay, ...
        Ecurrent, ...
        cfg, ...
        lpOptions);


    %% ========================================================
    % 13.5 真实严格因果回放
    %% ========================================================

    replay = ...
        replayBaseline( ...
        actualLoad(d,:)', ...
        actualPV(d,:)', ...
        plan.Wgrid, ...
        plan.WchBase, ...
        plan.WdisBase, ...
        Ecurrent, ...
        cfg);


    %% ========================================================
    % 13.6 保存
    %% ========================================================

    planGrid(d,:) = ...
        plan.Wgrid';


    planChargeBase(d,:) = ...
        plan.WchBase';


    planDischargeBase(d,:) = ...
        plan.WdisBase';


    planSOCBase(d,:) = ...
        plan.Ebase';


    actualCharge(d,:) = ...
        replay.Wch';


    actualDischarge(d,:) = ...
        replay.Wdis';


    actualSpill(d,:) = ...
        replay.Wspill';


    emergencyGrid(d,:) = ...
        replay.Wem';


    actualSOC(d,:) = ...
        replay.E';


    %% --------------------------------------------------------
    % 优化阶段认为的计划成本
    %% --------------------------------------------------------

    predictedPlanCostDay(d) = ...
        sum( ...
        predictedPriceDay ...
        .*plan.Wgrid);


    %% --------------------------------------------------------
    % ★最终计划购电结算
    %
    % 使用附件4真实实时价格
    %% --------------------------------------------------------

    actualPlanCostDay(d) = ...
        sum( ...
        actualPriceDay ...
        .*plan.Wgrid);


    %% --------------------------------------------------------
    % ★紧急购电
    %
    % 真实交易时刻价格 × 5
    %% --------------------------------------------------------

    emergencyCostDay(d) = ...
        cfg.emergencyFactor ...
        *sum( ...
        actualPriceDay ...
        .*replay.Wem);


    totalCostDay(d) = ...
        actualPlanCostDay(d) ...
        +emergencyCostDay(d);


    %% --------------------------------------------------------
    % SOC传递到下一天
    %% --------------------------------------------------------

    Ecurrent = ...
        replay.Eend;


    SOCend(d) = ...
        Ecurrent;


    %% --------------------------------------------------------
    % 进度
    %% --------------------------------------------------------

    if mod(d-1,20)==0 ...
            ||d==nDay

        fprintf( ...
            '[%03d/%03d] %s | Similar=%d | SOC=%.2f\n', ...
            d, ...
            nDay, ...
            string(predDates(d)), ...
            scenarioCount(d), ...
            Ecurrent);

    end

end


runtimeMin = ...
    toc(timerDispatch)/60;


%% ============================================================
% 14. 汇总
%% ============================================================

totalPlanEnergy = ...
    sum(planGrid,'all');


totalPredictedPlanCost = ...
    sum(predictedPlanCostDay);


totalActualPlanCost = ...
    sum(actualPlanCostDay);


totalEmergencyEnergy = ...
    sum(emergencyGrid,'all');


totalEmergencyCost = ...
    sum(emergencyCostDay);


totalCost = ...
    totalActualPlanCost ...
    +totalEmergencyCost;


totalCharge = ...
    sum(actualCharge,'all');


totalDischarge = ...
    sum(actualDischarge,'all');


totalSpill = ...
    sum(actualSpill,'all');


emergencyDays = ...
    sum( ...
    any( ...
    emergencyGrid>1e-8, ...
    2));


emergencySlots = ...
    nnz( ...
    emergencyGrid>1e-8);


planSimultaneousSlots = ...
    nnz( ...
    planChargeBase>1e-8 ...
    &planDischargeBase>1e-8);


actualSimultaneousSlots = ...
    nnz( ...
    actualCharge>1e-8 ...
    &actualDischarge>1e-8);


finalSOC = ...
    SOCend(end);


%% ============================================================
% 15. 检查SOC
%% ============================================================

socValues = ...
    actualSOC(:,2:end);


if any(socValues<cfg.Emin-1e-6,'all') ...
        ||any(socValues>cfg.Emax+1e-6,'all')

    error( ...
        '存在SOC越界。');

end


%% ============================================================
% 16. 输出结果
%% ============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' Q4-2最终结果\n');
fprintf(' AS-Ridge + Similar10 + Causal Affine\n');
fprintf('====================================================\n');


fprintf( ...
    '实时电价预测MAE：%.6f 元/kWh\n', ...
    priceMAE);


fprintf( ...
    '实时电价预测RMSE：%.6f 元/kWh\n', ...
    priceRMSE);


fprintf( ...
    '实时电价预测Bias：%+.6f 元/kWh\n', ...
    priceBias);


fprintf('\n');


fprintf( ...
    '全年计划购电量：%.2f kWh\n', ...
    totalPlanEnergy);


fprintf( ...
    '预测电价下计划目标费用：%.2f 元\n', ...
    totalPredictedPlanCost);


fprintf( ...
    '附件4真实价格结算计划购电费：%.2f 元\n', ...
    totalActualPlanCost);


fprintf('\n');


fprintf( ...
    '全年紧急购电量：%.2f kWh\n', ...
    totalEmergencyEnergy);


fprintf( ...
    '全年紧急购电费：%.2f 元\n', ...
    totalEmergencyCost);


fprintf('\n');


fprintf( ...
    '全年总成本：%.2f 元\n', ...
    totalCost);


fprintf('\n');


fprintf( ...
    '紧急购电天数：%d\n', ...
    emergencyDays);


fprintf( ...
    '紧急购电时段数：%d\n', ...
    emergencySlots);


fprintf( ...
    '年末SOC：%.6f kWh\n', ...
    finalSOC);


fprintf('\n');


fprintf( ...
    '基础计划同时充放电时段：%d\n', ...
    planSimultaneousSlots);


fprintf( ...
    '实际同时充放电时段：%d\n', ...
    actualSimultaneousSlots);


fprintf( ...
    '运行时间：%.2f min\n', ...
    runtimeMin);


fprintf('====================================================\n');


%% ============================================================
% 17. 汇总表
%% ============================================================

summaryTable = ...
    table( ...
    "AS-Ridge + Similar10 + CausalAffine", ...
    PRICE_KL, ...
    PRICE_KS, ...
    priceMAE, ...
    priceRMSE, ...
    priceBias, ...
    totalPlanEnergy, ...
    totalPredictedPlanCost, ...
    totalActualPlanCost, ...
    totalEmergencyEnergy, ...
    totalEmergencyCost, ...
    totalCost, ...
    totalCharge, ...
    totalDischarge, ...
    totalSpill, ...
    emergencyDays, ...
    emergencySlots, ...
    finalSOC, ...
    planSimultaneousSlots, ...
    actualSimultaneousSlots, ...
    runtimeMin, ...
    'VariableNames',{ ...
    'Model', ...
    'Price_kL', ...
    'Price_kS', ...
    'PriceMAE', ...
    'PriceRMSE', ...
    'PriceBias', ...
    'PlanEnergy_kWh', ...
    'PredictedPricePlanCost_Yuan', ...
    'ActualPricePlanCost_Yuan', ...
    'EmergencyEnergy_kWh', ...
    'EmergencyCost_Yuan', ...
    'TotalCost_Yuan', ...
    'ActualCharge_kWh', ...
    'ActualDischarge_kWh', ...
    'ActualSpill_kWh', ...
    'EmergencyDays', ...
    'EmergencySlots', ...
    'FinalSOC_kWh', ...
    'PlanSimultaneousSlots', ...
    'ActualSimultaneousSlots', ...
    'Runtime_Min'} ...
    );


%% ============================================================
% 18. 每日结果
%% ============================================================

dailyTable = ...
    table( ...
    predDates, ...
    SOCstart, ...
    SOCend, ...
    sum(planGrid,2), ...
    predictedPlanCostDay, ...
    actualPlanCostDay, ...
    sum(emergencyGrid,2), ...
    emergencyCostDay, ...
    totalCostDay, ...
    scenarioCount, ...
    meanSimilarDistance, ...
    'VariableNames',{ ...
    'Date', ...
    'SOCstart_kWh', ...
    'SOCend_kWh', ...
    'PlanEnergy_kWh', ...
    'PredictedPlanCost_Yuan', ...
    'ActualPlanCost_Yuan', ...
    'EmergencyEnergy_kWh', ...
    'EmergencyCost_Yuan', ...
    'TotalCost_Yuan', ...
    'SimilarCount', ...
    'MeanSimilarDistance'} ...
    );


%% ============================================================
% 19. 保存分析Excel
%% ============================================================

if isfile(resultExcelFile)

    delete(resultExcelFile);

end


writetable( ...
    summaryTable, ...
    resultExcelFile, ...
    'Sheet','汇总');


writetable( ...
    dailyTable, ...
    resultExcelFile, ...
    'Sheet','每日结果');


write144Matrix( ...
    resultExcelFile, ...
    '预测实时电价', ...
    predDates, ...
    priceForecast);


write144Matrix( ...
    resultExcelFile, ...
    '实际实时电价', ...
    predDates, ...
    actualPrice);


%% ============================================================
% 20. 写官方result4-2.xlsx
%% ============================================================

fprintf('\n开始写入官方 result4-2.xlsx...\n');


%% ============================================================
% 20.1 备份模板
%% ============================================================

backupFile = ...
    fullfile( ...
    baseDir, ...
    '附件5', ...
    [ ...
    'result4-2_backup_', ...
    char( ...
    datetime( ...
    'now', ...
    'Format','yyyyMMdd_HHmmss')), ...
    '.xlsx' ...
    ]);


copyfile( ...
    result4File, ...
    backupFile);


fprintf( ...
    '原result4-2已备份：\n%s\n', ...
    backupFile);


%% ============================================================
% 20.2 计划购电量
%
% B:EO = 144个原始时段
% EP   = 全天购电量
% EQ   = 全天购电费用
%
% ★按附件4真实实时电价结算
%% ============================================================

dailyPlanEnergy = ...
    sum(planGrid,2);


writematrix( ...
    planGrid, ...
    result4File, ...
    'Sheet','计划购电量', ...
    'Range','B2');


writematrix( ...
    dailyPlanEnergy, ...
    result4File, ...
    'Sheet','计划购电量', ...
    'Range','EP2');


writematrix( ...
    actualPlanCostDay, ...
    result4File, ...
    'Sheet','计划购电量', ...
    'Range','EQ2');


fprintf('计划购电量写入完成。\n');


%% ============================================================
% 20.3 充放电量
%% ============================================================

timeBlockName = {
    '0:00-4:00'
    '4:00-8:00'
    '8:00-12:00'
    '12:00-16:00'
    '16:00-20:00'
    '20:00-24:00'
    };


nBlock = ...
    6;


charge4h = ...
    zeros(nDay,nBlock);


discharge4h = ...
    zeros(nDay,nBlock);


for d = 1:nDay

    for b = 1:nBlock

        s1 = ...
            (b-1)*24+1;


        s2 = ...
            b*24;


        charge4h(d,b) = ...
            sum( ...
            actualCharge(d,s1:s2));


        discharge4h(d,b) = ...
            sum( ...
            actualDischarge(d,s1:s2));

    end

end


cdRows = ...
    cell( ...
    nDay*nBlock, ...
    6);


r = ...
    1;


for d = 1:nDay

    for b = 1:nBlock

        %% 日期
        if b==1

            cdRows{r,1} = ...
                datestr( ...
                predDates(d), ...
                'yyyy-mm-dd');

        else

            cdRows{r,1} = ...
                '';

        end


        %% 时间段
        cdRows{r,2} = ...
            timeBlockName{b};


        %% 充电量
        cdRows{r,3} = ...
            charge4h(d,b);


        %% 放电量
        cdRows{r,4} = ...
            discharge4h(d,b);


        %% SOC
        if b==1

            cdRows{r,5} = ...
                '0:00';


            cdRows{r,6} = ...
                SOCstart(d);


        elseif b==2

            cdRows{r,5} = ...
                '24:00';


            cdRows{r,6} = ...
                SOCend(d);


        else

            cdRows{r,5} = ...
                '';


            cdRows{r,6} = ...
                [];

        end


        r = ...
            r+1;

    end

end


%% 先清旧结果
clearCD = ...
    repmat( ...
    {''}, ...
    2500, ...
    6);


writecell( ...
    clearCD, ...
    result4File, ...
    'Sheet','充放电量', ...
    'Range','A2');


%% 再写新结果
writecell( ...
    cdRows, ...
    result4File, ...
    'Sheet','充放电量', ...
    'Range','A2');


fprintf('充放电量写入完成。\n');


%% ============================================================
% 20.4 紧急购电量
%
% TIMEFIX：
%
% slot1 = 00:00-00:10
% slot2 = 00:10-00:20
% ...
% slot144 = 23:50-24:00
%% ============================================================

emergencyRows = ...
    cell(0,3);


rowOut = ...
    0;


for d = 1:nDay

    x = ...
        emergencyGrid(d,:);


    active = ...
        x>1e-8;


    if ~any(active)

        continue;

    end


    %% --------------------------------------------------------
    % 找连续区间
    %% --------------------------------------------------------

    edge = ...
        diff( ...
        [ ...
        false, ...
        active, ...
        false ...
        ]);


    starts = ...
        find(edge==1);


    ends = ...
        find(edge==-1)-1;


    for k = 1:length(starts)

        rowOut = ...
            rowOut+1;


        if k==1

            emergencyRows{rowOut,1} = ...
                datestr( ...
                predDates(d), ...
                'yyyy-mm-dd');

        else

            emergencyRows{rowOut,1} = ...
                '';

        end


        emergencyRows{rowOut,2} = ...
            makeEmergencyTimeRange( ...
            starts(k), ...
            ends(k));


        emergencyRows{rowOut,3} = ...
            sum( ...
            x( ...
            starts(k):ends(k)));

    end

end


%% 清除旧结果
clearEmergency = ...
    repmat( ...
    {''}, ...
    5000, ...
    3);


writecell( ...
    clearEmergency, ...
    result4File, ...
    'Sheet','紧急购电量', ...
    'Range','A2');


%% 写入新结果
if ~isempty(emergencyRows)

    writecell( ...
        emergencyRows, ...
        result4File, ...
        'Sheet','紧急购电量', ...
        'Range','A2');

end


fprintf('紧急购电量写入完成。\n');


%% ============================================================
% 21. result4-2核对
%% ============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' result4-2.xlsx 写入完成\n');
fprintf('====================================================\n');


fprintf( ...
    '计划购电量：%.2f kWh\n', ...
    totalPlanEnergy);


fprintf( ...
    '计划购电费：%.2f 元\n', ...
    totalActualPlanCost);


fprintf( ...
    '紧急购电量：%.2f kWh\n', ...
    totalEmergencyEnergy);


fprintf( ...
    '紧急购电费：%.2f 元\n', ...
    totalEmergencyCost);


fprintf( ...
    '全年总成本：%.2f 元\n', ...
    totalCost);


fprintf( ...
    '年末SOC：%.6f kWh\n', ...
    finalSOC);


fprintf('\n官方文件：\n%s\n', ...
    result4File);


fprintf('====================================================\n');


%% ============================================================
% 22. 保存MAT
%% ============================================================

save( ...
    resultMatFile, ...
    'summaryTable', ...
    'dailyTable', ...
    'predDates', ...
    'predLoad', ...
    'predPV', ...
    'actualLoad', ...
    'actualPV', ...
    'forecastNet', ...
    'residualNet', ...
    'priceForecast', ...
    'actualPrice', ...
    'priceMAE', ...
    'priceRMSE', ...
    'priceBias', ...
    'planGrid', ...
    'planChargeBase', ...
    'planDischargeBase', ...
    'planSOCBase', ...
    'actualCharge', ...
    'actualDischarge', ...
    'actualSpill', ...
    'emergencyGrid', ...
    'actualSOC', ...
    'SOCstart', ...
    'SOCend', ...
    'scenarioCount', ...
    'meanSimilarDistance', ...
    'predictedPlanCostDay', ...
    'actualPlanCostDay', ...
    'emergencyCostDay', ...
    'totalCostDay', ...
    'totalCost', ...
    'cfg', ...
    'runtimeMin', ...
    '-v7.3');


%% ============================================================
% 23. SOC图
%% ============================================================

fig1 = ...
    figure( ...
    'Color','w', ...
    'Position',[100,100,1300,650]);


plot( ...
    predDates, ...
    SOCend, ...
    'LineWidth',1.1);


hold on;


yline( ...
    cfg.Emin, ...
    '--', ...
    'SOC下限');


yline( ...
    cfg.Emax, ...
    '--', ...
    'SOC上限');


yline( ...
    6000, ...
    ':', ...
    '6000 kWh参考线');


xlabel('日期');


ylabel('日末SOC / kWh');


title( ...
    '问题4-2 AS-Ridge + Similar10 日末SOC');


grid on;


exportgraphics( ...
    fig1, ...
    figSOCFile, ...
    'Resolution',300);


%% ============================================================
% 24. 电价预测示例图
%% ============================================================

showDay = ...
    min(100,nDay);


fig2 = ...
    figure( ...
    'Color','w', ...
    'Position',[100,100,1200,600]);


plot( ...
    1:144, ...
    actualPrice(showDay,:), ...
    'LineWidth',1.2);


hold on;


plot( ...
    1:144, ...
    priceForecast(showDay,:), ...
    '--', ...
    'LineWidth',1.2);


xlabel('10 min时段');


ylabel('电价 / 元·kWh^{-1}');


title( ...
    sprintf( ...
    '实时电价预测示例：%s', ...
    string(predDates(showDay))));


legend( ...
    '附件4实际电价', ...
    '0时预测电价', ...
    'Location','best');


grid on;


exportgraphics( ...
    fig2, ...
    figPriceFile, ...
    'Resolution',300);


fprintf('\n');
fprintf('====================================================\n');
fprintf(' Q4-2全部运行完成\n');
fprintf('====================================================\n');


fprintf( ...
    '分析Excel：\n%s\n', ...
    resultExcelFile);


fprintf( ...
    '结果MAT：\n%s\n', ...
    resultMatFile);


fprintf( ...
    '官方result4-2：\n%s\n', ...
    result4File);


fprintf('====================================================\n');


%% ============================================================
% 局部函数1
%
% Similar10 Causal Affine计划
%% ============================================================

function plan = solveCausalAffinePlan( ...
    forecastNet, ...
    residualScenarios, ...
    price, ...
    Estart, ...
    cfg, ...
    options)


[K,N] = ...
    size(residualScenarios);


price = ...
    price(:);


%% ------------------------------------------------------------
% 功率 -> 10min电量
%% ------------------------------------------------------------

Wbase = ...
    forecastNet(:)' ...
    *cfg.dt;


R = ...
    residualScenarios ...
    *cfg.dt;


Rp = ...
    max(R,0);


Rn = ...
    max(-R,0);


%% ============================================================
% 变量
%% ============================================================

idxG = ...
    1:N;


idxC0 = ...
    N+(1:N);


idxD0 = ...
    2*N+(1:N);


idxACP = ...
    3*N+(1:N);


idxACN = ...
    4*N+(1:N);


idxADP = ...
    5*N+(1:N);


idxADN = ...
    6*N+(1:N);


base = ...
    7*N;


idxEbase = ...
    base+(1:N+1);


base = ...
    base+N+1;


idxSpBase = ...
    base+(1:N);


base = ...
    base+N;


idxE = ...
    reshape( ...
    base+(1:K*(N+1)), ...
    N+1,K)';


base = ...
    base+K*(N+1);


idxEm = ...
    reshape( ...
    base+(1:K*N), ...
    N,K)';


base = ...
    base+K*N;


idxSp = ...
    reshape( ...
    base+(1:K*N), ...
    N,K)';


nVar = ...
    base+K*N;


%% ============================================================
% 目标函数
%% ============================================================

f = ...
    zeros(nVar,1);


%% ------------------------------------------------------------
% 普通购电：
% 使用今天预测实时电价
%% ------------------------------------------------------------

f(idxG) = ...
    price;


%% ------------------------------------------------------------
% 情景期望紧急购电成本
%% ------------------------------------------------------------

for s = 1:K

    f(idxEm(s,:)) = ...
        cfg.emergencyFactor ...
        *price/K;

end


%% ------------------------------------------------------------
% 期望充放电吞吐tie-break
%% ------------------------------------------------------------

mRp = ...
    mean(Rp,1)';


mRn = ...
    mean(Rn,1)';


f(idxC0) = ...
    cfg.cyclePenalty;


f(idxD0) = ...
    cfg.cyclePenalty;


f(idxACP) = ...
    -cfg.cyclePenalty ...
    *mRp;


f(idxACN) = ...
    cfg.cyclePenalty ...
    *mRn;


f(idxADP) = ...
    cfg.cyclePenalty ...
    *mRp;


f(idxADN) = ...
    -cfg.cyclePenalty ...
    *mRn;


%% ============================================================
% 等式约束
%% ============================================================

nEq = ...
    2*N+1 ...
    +2*K*N ...
    +K;


nnzEq = ...
    8*N+1 ...
    +17*K*N ...
    +K;


rows = ...
    zeros(nnzEq,1);


cols = ...
    zeros(nnzEq,1);


vals = ...
    zeros(nnzEq,1);


beq = ...
    zeros(nEq,1);


q = ...
    0;


%% ============================================================
% 基础预测路径
%% ============================================================

for t = 1:N

    %% --------------------------------------------------------
    % 供需平衡
    %% --------------------------------------------------------

    r = ...
        t;


    js = [
        idxG(t)
        idxD0(t)
        idxC0(t)
        idxSpBase(t)
        ];


    vs = [
         1
         1
        -1
        -1
        ];


    rows(q+(1:4)) = ...
        r;


    cols(q+(1:4)) = ...
        js;


    vals(q+(1:4)) = ...
        vs;


    q = ...
        q+4;


    beq(r) = ...
        Wbase(t);


    %% --------------------------------------------------------
    % SOC递推
    %% --------------------------------------------------------

    r = ...
        N+t;


    js = [
        idxEbase(t)
        idxEbase(t+1)
        idxC0(t)
        idxD0(t)
        ];


    vs = [
        -1
         1
        -cfg.etaCh
         1/cfg.etaDis
        ];


    rows(q+(1:4)) = ...
        r;


    cols(q+(1:4)) = ...
        js;


    vals(q+(1:4)) = ...
        vs;


    q = ...
        q+4;

end


%% 初始SOC
rows(q+1) = ...
    2*N+1;


cols(q+1) = ...
    idxEbase(1);


vals(q+1) = ...
    1;


q = ...
    q+1;


beq(2*N+1) = ...
    Estart;


%% ============================================================
% Similar10场景
%% ============================================================

for s = 1:K

    for t = 1:N

        %% ----------------------------------------------------
        % 供需平衡
        %% ----------------------------------------------------

        r = ...
            2*N+1 ...
            +(s-1)*N ...
            +t;


        js = [
            idxG(t)
            idxC0(t)
            idxD0(t)
            idxACP(t)
            idxACN(t)
            idxADP(t)
            idxADN(t)
            idxEm(s,t)
            idxSp(s,t)
            ];


        vs = [
             1
            -1
             1
             Rp(s,t)
            -Rn(s,t)
             Rp(s,t)
            -Rn(s,t)
             1
            -1
            ];


        rows(q+(1:9)) = ...
            r;


        cols(q+(1:9)) = ...
            js;


        vals(q+(1:9)) = ...
            vs;


        q = ...
            q+9;


        beq(r) = ...
            Wbase(t) ...
            +R(s,t);


        %% ----------------------------------------------------
        % SOC
        %% ----------------------------------------------------

        r = ...
            2*N+1 ...
            +K*N ...
            +(s-1)*N ...
            +t;


        js = [
            idxE(s,t)
            idxE(s,t+1)
            idxC0(t)
            idxD0(t)
            idxACP(t)
            idxACN(t)
            idxADP(t)
            idxADN(t)
            ];


        vs = [
            -1
             1
            -cfg.etaCh
             1/cfg.etaDis
             cfg.etaCh*Rp(s,t)
            -cfg.etaCh*Rn(s,t)
             Rp(s,t)/cfg.etaDis
            -Rn(s,t)/cfg.etaDis
            ];


        rows(q+(1:8)) = ...
            r;


        cols(q+(1:8)) = ...
            js;


        vals(q+(1:8)) = ...
            vs;


        q = ...
            q+8;

    end


    %% 情景初始SOC
    r = ...
        2*N+1 ...
        +2*K*N ...
        +s;


    rows(q+1) = ...
        r;


    cols(q+1) = ...
        idxE(s,1);


    vals(q+1) = ...
        1;


    q = ...
        q+1;


    beq(r) = ...
        Estart;

end


Aeq = ...
    sparse( ...
    rows(1:q), ...
    cols(1:q), ...
    vals(1:q), ...
    nEq,nVar);


%% ============================================================
% 仿射充放电功率约束
%% ============================================================

nIneq = ...
    4*K*N;


rows = ...
    zeros(12*K*N,1);


cols = ...
    zeros(12*K*N,1);


vals = ...
    zeros(12*K*N,1);


b = ...
    zeros(nIneq,1);


q = ...
    0;


for s = 1:K

    for t = 1:N

        r0 = ...
            4*((s-1)*N+t-1);


        %% C <= Wmax
        js = [
            idxC0(t)
            idxACP(t)
            idxACN(t)
            ];


        vs = [
             1
            -Rp(s,t)
             Rn(s,t)
            ];


        rows(q+(1:3)) = ...
            r0+1;


        cols(q+(1:3)) = ...
            js;


        vals(q+(1:3)) = ...
            vs;


        q = ...
            q+3;


        b(r0+1) = ...
            cfg.Wmax;


        %% C >= 0
        rows(q+(1:3)) = ...
            r0+2;


        cols(q+(1:3)) = ...
            js;


        vals(q+(1:3)) = ...
            -vs;


        q = ...
            q+3;


        %% D <= Wmax
        js = [
            idxD0(t)
            idxADP(t)
            idxADN(t)
            ];


        vs = [
             1
             Rp(s,t)
            -Rn(s,t)
            ];


        rows(q+(1:3)) = ...
            r0+3;


        cols(q+(1:3)) = ...
            js;


        vals(q+(1:3)) = ...
            vs;


        q = ...
            q+3;


        b(r0+3) = ...
            cfg.Wmax;


        %% D >= 0
        rows(q+(1:3)) = ...
            r0+4;


        cols(q+(1:3)) = ...
            js;


        vals(q+(1:3)) = ...
            -vs;


        q = ...
            q+3;

    end

end


A = ...
    sparse( ...
    rows, ...
    cols, ...
    vals, ...
    nIneq,nVar);


%% ============================================================
% 上下界
%% ============================================================

lb = ...
    zeros(nVar,1);


ub = ...
    inf(nVar,1);


ub(idxC0) = ...
    cfg.Wmax;


ub(idxD0) = ...
    cfg.Wmax;


ub([
    idxACP
    idxACN
    idxADP
    idxADN
    ]) = ...
    1;


lb(idxEbase) = ...
    cfg.Emin;


ub(idxEbase) = ...
    cfg.Emax;


lb(idxE(:)) = ...
    cfg.Emin;


ub(idxE(:)) = ...
    cfg.Emax;


%% ============================================================
% 求解
%% ============================================================

[x,~,exitflag,output] = ...
    linprog( ...
    f, ...
    A,b, ...
    Aeq,beq, ...
    lb,ub, ...
    options);


if exitflag<=0

    error( ...
        'Q4-2 causal affine LP失败：%s', ...
        output.message);

end


plan.Wgrid = ...
    x(idxG);


plan.WchBase = ...
    x(idxC0);


plan.WdisBase = ...
    x(idxD0);


plan.Ebase = ...
    x(idxEbase);


end


%% ============================================================
% 局部函数2
%
% 真实数据因果回放
%% ============================================================

function replay = replayBaseline( ...
    Pload, ...
    Pv, ...
    Wgrid, ...
    WchPlan, ...
    WdisPlan, ...
    Estart, ...
    cfg)


N = ...
    numel(Wgrid);


Wload = ...
    Pload(:)*cfg.dt;


Wpv = ...
    Pv(:)*cfg.dt;


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


E = ...
    zeros(N+1,1);


E(1) = ...
    Estart;


for t = 1:N

    ec = ...
        E(t);


    c = ...
        min( ...
        max(WchPlan(t),0), ...
        cfg.Wmax);


    d = ...
        min( ...
        max(WdisPlan(t),0), ...
        cfg.Wmax);


    en = ...
        ec ...
        +cfg.etaCh*c ...
        -d/cfg.etaDis;


    %% --------------------------------------------------------
    % SOC低于下限 → 减少放电
    %% --------------------------------------------------------

    if en<cfg.Emin

        rd = ...
            min( ...
            d, ...
            (cfg.Emin-en) ...
            *cfg.etaDis);


        d = ...
            d-rd;


        en = ...
            ec ...
            +cfg.etaCh*c ...
            -d/cfg.etaDis;

    end


    %% --------------------------------------------------------
    % SOC超过上限 → 减少充电
    %% --------------------------------------------------------

    if en>cfg.Emax

        rc = ...
            min( ...
            c, ...
            (en-cfg.Emax) ...
            /cfg.etaCh);


        c = ...
            c-rc;


        en = ...
            ec ...
            +cfg.etaCh*c ...
            -d/cfg.etaDis;

    end


    %% --------------------------------------------------------
    % 实际缺口
    %% --------------------------------------------------------

    residual = ...
        Wload(t) ...
        -Wpv(t) ...
        -Wgrid(t) ...
        -(d-c);


    %% ========================================================
    % 缺电
    %% ========================================================

    if residual>1e-12

        %% 先减少充电

        rc = ...
            min( ...
            [ ...
            residual, ...
            c, ...
            max( ...
            (en-cfg.Emin) ...
            /cfg.etaCh, ...
            0) ...
            ]);


        c = ...
            c-rc;


        residual = ...
            residual-rc;


        en = ...
            en ...
            -cfg.etaCh*rc;


        %% 再增加放电
        if residual>1e-12

            ad = ...
                min( ...
                residual, ...
                min( ...
                cfg.Wmax-d, ...
                cfg.etaDis ...
                *max( ...
                en-cfg.Emin, ...
                0)));


            d = ...
                d+ad;


            residual = ...
                residual-ad;

        end


        %% 最后紧急购电
        Wem(t) = ...
            max( ...
            residual, ...
            0);


    %% ========================================================
    % 富余
    %% ========================================================

    elseif residual<-1e-12

        surplus = ...
            -residual;


        %% 先减少放电
        rd = ...
            min( ...
            [ ...
            surplus, ...
            d, ...
            cfg.etaDis ...
            *max( ...
            cfg.Emax-en, ...
            0) ...
            ]);


        d = ...
            d-rd;


        surplus = ...
            surplus-rd;


        en = ...
            en ...
            +rd/cfg.etaDis;


        %% 再增加充电
        if surplus>1e-12

            ac = ...
                min( ...
                surplus, ...
                min( ...
                cfg.Wmax-c, ...
                max( ...
                cfg.Emax-en, ...
                0) ...
                /cfg.etaCh));


            c = ...
                c+ac;


            surplus = ...
                surplus-ac;

        end


        %% 最后记为富余
        Wspill(t) = ...
            max( ...
            surplus, ...
            0);

    end


    Wch(t) = ...
        c;


    Wdis(t) = ...
        d;


    E(t+1) = ...
        ec ...
        +cfg.etaCh*c ...
        -d/cfg.etaDis;


    if E(t+1)<cfg.Emin-1e-6 ...
            ||E(t+1)>cfg.Emax+1e-6

        error( ...
            '实际SOC越界：t=%d，SOC=%.9f', ...
            t,E(t+1));

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


replay.E = ...
    E;


replay.Eend = ...
    E(end);


end


%% ============================================================
% 局部函数3
%
% TIMEFIX紧急购电时间
%
% slot1 = 00:00-00:10
% slot37 = 06:00-06:10
%% ============================================================

function txt = makeEmergencyTimeRange(s,e)


startMinute = ...
    10*(s-1);


endMinute = ...
    10*e;


txt = ...
    sprintf( ...
    '%s-%s', ...
    formatTimeLabel(startMinute), ...
    formatTimeLabel(endMinute));


end


%% ============================================================
% 局部函数4
% 分钟转时间
%% ============================================================

function txt = formatTimeLabel(totalMinute)


dayAdd = ...
    floor( ...
    totalMinute/1440);


minuteOfDay = ...
    mod( ...
    totalMinute, ...
    1440);


hh = ...
    floor( ...
    minuteOfDay/60);


mm = ...
    mod( ...
    minuteOfDay, ...
    60);


if dayAdd==0

    txt = ...
        sprintf( ...
        '%d:%02d', ...
        hh,mm);

else

    txt = ...
        sprintf( ...
        '%d:%02d+1', ...
        hh,mm);

end


end


%% ============================================================
% 局部函数5
% 写144点矩阵
%% ============================================================

function write144Matrix( ...
    filename, ...
    sheetName, ...
    dates, ...
    M)


dateText = ...
    string( ...
    dates, ...
    'yyyy-MM-dd');


header = ...
    cell(1,145);


header{1} = ...
    '日期';


%% ------------------------------------------------------------
% B:EO：
%
% 00:10,00:20,...,23:50,00:00+1
%% ------------------------------------------------------------

for t = 1:143

    totalMinute = ...
        10*t;


    hh = ...
        floor( ...
        totalMinute/60);


    mm = ...
        mod( ...
        totalMinute,60);


    header{t+1} = ...
        sprintf( ...
        '%02d:%02d', ...
        hh,mm);

end


header{145} = ...
    '00:00+1';


writecell( ...
    header, ...
    filename, ...
    'Sheet',sheetName, ...
    'Range','A1');


writecell( ...
    cellstr(dateText), ...
    filename, ...
    'Sheet',sheetName, ...
    'Range','A2');


writematrix( ...
    M, ...
    filename, ...
    'Sheet',sheetName, ...
    'Range','B2');


end