%% ============================================================
% 2026 C题 问题2
%
% Similar10 + Causal Affine Recourse LP
%
% 独立正式版：
% 1. 直接读取用户电脑上的附件
% 2. 负载、光伏均使用AS-Ridge预测
% 3. 最近30天中选择10个最相似日
% 4. 真实净负荷残差作为情景
% 5. 储能采用当前残差因果仿射响应
% 6. 实际数据逐10min因果回放
% 7. 最终写入官方附件5/result2.xlsx
%
% ============================================================
%
% TIMEFIX：
%
% 附件原始144列直接使用，不进行任何循环移位。
%
% slot1   = 第1个10min时段
% slot36  = 6:00
% slot72  = 12:00
% slot108 = 18:00
% slot144 = 次日0:00
%
% 输出result2时 planGrid 直接写入B:EO。
%
% ============================================================

clear;
clc;
close all;

rng(20260912,'twister');


fprintf('====================================================\n');
fprintf(' 问题2 Similar10 + Causal Affine Recourse\n');
fprintf(' TIMEFIX + 官方 result2 输出\n');
fprintf('====================================================\n\n');


%% ============================================================
% 1. 路径
%% ============================================================

baseDir = ...
    'E:\数模\2026年正式比赛\CUMCM2026Problems\C题\附件';


actualFile = ...
    fullfile( ...
    baseDir, ...
    '附件2.xlsx');


priceFile = ...
    fullfile( ...
    baseDir, ...
    '附件1.xlsx');


predictionFile = ...
    fullfile( ...
    baseDir, ...
    'Q2_16combo_4models_predictions.mat');


result2File = ...
    fullfile( ...
    baseDir, ...
    '附件5', ...
    'result2.xlsx');


outMat = ...
    fullfile( ...
    baseDir, ...
    'Q2_P2_SIMILAR10_RESULT2_FINAL.mat');


outXlsx = ...
    fullfile( ...
    baseDir, ...
    'Q2_P2_SIMILAR10_RESULT2_FINAL.xlsx');


filesNeed = {
    actualFile
    priceFile
    predictionFile
    result2File
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


%% 最近多少天内找相似日
cfg.historyWindowDays = ...
    30;


%% 至少有多少历史日才启用Similar10
cfg.minHistoryDays = ...
    7;


%% 选择几个最相似日
cfg.similarDayCount = ...
    10;


%% 极小充放电吞吐惩罚
% 只用于LP多个等价解的tie-break
cfg.cyclePenalty = ...
    1e-5;


%% ============================================================
% 3. 日期
%% ============================================================

datesAll = ...
    ( ...
    datetime(2025,1,1): ...
    days(1): ...
    datetime(2025,12,31) ...
    )';


targetDays = ...
    32:365;


predDates = ...
    datesAll(targetDays);


nDay = ...
    length(targetDays);


nTime = ...
    144;


if nDay~=334

    error('目标日期数量应为334天。');

end


%% ============================================================
% 4. 读取附件2真实负载和光伏
%
% TIMEFIX：
% 直接保持原始144列顺序
%% ============================================================

fprintf('读取附件2...\n');


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
        '附件2小区负载必须为365×144。');

end


if ~isequal(size(pvRaw),[365,144])

    error( ...
        '附件2光伏实际功率必须为365×144。');

end


if any(~isfinite(loadRaw),'all') ...
        || any(~isfinite(pvRaw),'all')

    error( ...
        '附件2中存在NaN或非有限值。');

end


actualLoad = ...
    loadRaw(targetDays,:);


actualPV = ...
    pvRaw(targetDays,:);


fprintf('附件2读取完成。\n\n');


%% ============================================================
% 5. 读取AS-Ridge预测
%% ============================================================

fprintf('读取预测缓存...\n');


P = ...
    load(predictionFile);


requiredVariables = {
    'predLoad'
    'predPV'
    'modelNames'
    };


for i = 1:length(requiredVariables)

    if ~isfield(P,requiredVariables{i})

        error( ...
            '预测缓存缺少变量：%s', ...
            requiredVariables{i});

    end

end


modelNames = ...
    string(P.modelNames(:));


asID = ...
    find( ...
    strcmpi( ...
    modelNames, ...
    'AS-Ridge'), ...
    1);


if isempty(asID)

    error( ...
        '预测缓存中找不到AS-Ridge模型。');

end


fprintf( ...
    'AS-Ridge模型位于第%d层。\n', ...
    asID);


if size(P.predLoad,1)~=nDay ...
        || size(P.predLoad,2)~=nTime

    error( ...
        'predLoad尺寸不正确。');

end


if size(P.predPV,1)~=nDay ...
        || size(P.predPV,2)~=nTime

    error( ...
        'predPV尺寸不正确。');

end


%% ------------------------------------------------------------
% TIMEFIX：
% 直接使用，不旋转
%% ------------------------------------------------------------

predLoad = ...
    P.predLoad(:,:,asID);


predPV = ...
    P.predPV(:,:,asID);


predLoad = ...
    max(predLoad,0);


predPV = ...
    max(predPV,0);


fprintf('负载：AS-Ridge\n');
fprintf('光伏：AS-Ridge\n');
fprintf('预测时间轴：附件原始144列顺序。\n\n');


%% ============================================================
% 6. 电价
%% ============================================================

fprintf('读取附件1电价...\n');


Tprice = ...
    readtable( ...
    priceFile, ...
    'VariableNamingRule','preserve');


price = ...
    Tprice{:,2};


price = ...
    price(:);


if length(price)~=144

    error( ...
        '附件1电价必须为144个10min时段。');

end


if any(~isfinite(price)) ...
        || any(price<0)

    error( ...
        '附件1存在非法电价。');

end


fprintf('附件1电价读取完成。\n\n');


%% ============================================================
% 7. 净负荷及残差
%
% 注意：
%
% 本Similar10版本严格保持原P2思路：
% 不使用问题2原来的Q0.8修正。
%
% forecastNet = 负载预测 - 光伏预测
%
% residualNet =
% 实际净负荷 - 预测净负荷
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
% 8. LP设置
%% ============================================================

options = ...
    optimoptions( ...
    'linprog', ...
    'Algorithm','dual-simplex-highs', ...
    'Display','none');


%% ============================================================
% 9. 初始化
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


planCostDay = ...
    zeros(nDay,1);


emergencyCostDay = ...
    zeros(nDay,1);


totalCostDay = ...
    zeros(nDay,1);


%% ============================================================
% 10. 全年逐日Similar10调度
%% ============================================================

fprintf('====================================================\n');
fprintf(' 开始全年 Similar10 调度\n');
fprintf('====================================================\n\n');


Ecurrent = ...
    cfg.Einitial;


timerMain = ...
    tic;


for d = 1:nDay

    SOCstart(d) = ...
        Ecurrent;


    %% --------------------------------------------------------
    % 10.1 候选历史日
    %% --------------------------------------------------------

    histStart = ...
        max( ...
        1, ...
        d-cfg.historyWindowDays);


    histEnd = ...
        d-1;


    nHistory = ...
        histEnd-histStart+1;


    %% --------------------------------------------------------
    % 历史天数足够：
    % 最近30天中找最相似的10天
    %% --------------------------------------------------------

    if nHistory>=cfg.minHistoryDays

        candidateDays = ...
            (histStart:histEnd)';


        %% 当前预测尺度
        loadScale = ...
            max( ...
            mean( ...
            abs(predLoad(d,:))), ...
            1);


        pvScale = ...
            max( ...
            mean( ...
            abs(predPV(d,:))), ...
            1);


        %% -----------------------------------------------
        % 负载预测曲线相似度
        %% -----------------------------------------------

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


        %% -----------------------------------------------
        % 光伏预测曲线相似度
        %% -----------------------------------------------

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


        %% -----------------------------------------------
        % 综合距离
        %% -----------------------------------------------

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


        %% -----------------------------------------------
        % 直接使用这些相似日的真实净负荷残差路径
        %% -----------------------------------------------

        residualScenarios = ...
            residualNet(selectedDays,:);


        scenarioCount(d) = ...
            keepN;


        meanSimilarDistance(d) = ...
            mean( ...
            totalDistance(keep));


    %% --------------------------------------------------------
    % 历史数据不足：
    % 只使用零残差场景
    %% --------------------------------------------------------

    else

        residualScenarios = ...
            zeros(1,nTime);


        scenarioCount(d) = ...
            1;


        meanSimilarDistance(d) = ...
            NaN;

    end


    %% ========================================================
    % 10.2 日前因果仿射计划
    %% ========================================================

    plan = ...
        solveCausalAffinePlan( ...
        forecastNet(d,:), ...
        residualScenarios, ...
        price, ...
        Ecurrent, ...
        cfg, ...
        options);


    %% ========================================================
    % 10.3 使用当天真实负载和光伏逐10min回放
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
    % 10.4 保存结果
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


    planCostDay(d) = ...
        sum( ...
        price ...
        .*plan.Wgrid);


    emergencyCostDay(d) = ...
        sum( ...
        cfg.emergencyFactor ...
        *price ...
        .*replay.Wem);


    totalCostDay(d) = ...
        planCostDay(d) ...
        +emergencyCostDay(d);


    Ecurrent = ...
        replay.Eend;


    SOCend(d) = ...
        Ecurrent;


    %% ========================================================
    % 进度
    %% ========================================================

    if mod(d-1,20)==0 ...
            || d==nDay

        fprintf( ...
            '[%03d/%03d] %s | 情景=%d | SOC=%.2f\n', ...
            d, ...
            nDay, ...
            string(predDates(d)), ...
            scenarioCount(d), ...
            Ecurrent);

    end

end


runtimeSeconds = ...
    toc(timerMain);


runtimeMinutes = ...
    runtimeSeconds/60;


%% ============================================================
% 11. 汇总结果
%% ============================================================

totalPlanEnergy = ...
    sum(planGrid,'all');


totalPlanCost = ...
    sum(planCostDay);


totalEmergencyEnergy = ...
    sum(emergencyGrid,'all');


totalEmergencyCost = ...
    sum(emergencyCostDay);


totalCost = ...
    totalPlanCost ...
    +totalEmergencyCost;


totalActualSpill = ...
    sum(actualSpill,'all');


totalCharge = ...
    sum(actualCharge,'all');


totalDischarge = ...
    sum(actualDischarge,'all');


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


allSOC = ...
    actualSOC(:,2:end);


if any(allSOC<cfg.Emin-1e-5,'all') ...
        || any(allSOC>cfg.Emax+1e-5,'all')

    error( ...
        '实际执行SOC存在越界。');

end


%% ============================================================
% 12. MATLAB命令窗口结果
%% ============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' Similar10 + Causal Affine 最终结果\n');
fprintf('====================================================\n');


fprintf( ...
    '全年计划购电量：%.2f kWh\n', ...
    totalPlanEnergy);


fprintf( ...
    '全年计划购电费：%.2f 元\n', ...
    totalPlanCost);


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
    '实际充电量：%.2f kWh\n', ...
    totalCharge);


fprintf( ...
    '实际放电量：%.2f kWh\n', ...
    totalDischarge);


fprintf( ...
    '实际富余电量：%.2f kWh\n', ...
    totalActualSpill);


fprintf('\n');


fprintf( ...
    '紧急购电天数：%d\n', ...
    emergencyDays);


fprintf( ...
    '紧急购电10min时段：%d\n', ...
    emergencySlots);


fprintf('\n');


fprintf( ...
    '基础计划同时充放电时段：%d\n', ...
    planSimultaneousSlots);


fprintf( ...
    '实际同时充放电时段：%d\n', ...
    actualSimultaneousSlots);


fprintf('\n');


fprintf( ...
    '年末SOC：%.6f kWh\n', ...
    SOCend(end));


fprintf( ...
    '全年最低SOC：%.6f kWh\n', ...
    min(allSOC,[],'all'));


fprintf( ...
    '全年最高SOC：%.6f kWh\n', ...
    max(allSOC,[],'all'));


fprintf('\n');


fprintf( ...
    '运行时间：%.2f min\n', ...
    runtimeMinutes);


fprintf('====================================================\n');


%% ============================================================
% 13. 备份官方result2
%% ============================================================

fprintf('\n');
fprintf('开始写入官方 result2.xlsx...\n');


backupFile = ...
    fullfile( ...
    baseDir, ...
    '附件5', ...
    [ ...
    'result2_backup_SIMILAR10_', ...
    char( ...
    datetime( ...
    'now', ...
    'Format','yyyyMMdd_HHmmss')), ...
    '.xlsx' ...
    ]);


copyfile( ...
    result2File, ...
    backupFile);


fprintf( ...
    '原result2已备份：\n%s\n', ...
    backupFile);


%% ============================================================
% 14. 写result2：计划购电量
%
% B:EO = 144时段
% EP   = 全天购电量
% EQ   = 全天购电费
%
% TIMEFIX：
% planGrid直接写入，不旋转
%% ============================================================

planOut = ...
    planGrid;


dailyPlanEnergy = ...
    sum( ...
    planOut, ...
    2);


if ~isequal( ...
        size(planOut), ...
        [334,144])

    error( ...
        'planGrid必须为334×144。');

end


writematrix( ...
    planOut, ...
    result2File, ...
    'Sheet','计划购电量', ...
    'Range','B2');


writematrix( ...
    dailyPlanEnergy, ...
    result2File, ...
    'Sheet','计划购电量', ...
    'Range','EP2');


writematrix( ...
    planCostDay, ...
    result2File, ...
    'Sheet','计划购电量', ...
    'Range','EQ2');


fprintf('计划购电量写入完成。\n');


%% ============================================================
% 15. 写result2：充放电量
%
% 每日6个4h区间：
%
% 0:00-4:00
% 4:00-8:00
% 8:00-12:00
% 12:00-16:00
% 16:00-20:00
% 20:00-24:00
%
% 每24个10min点 = 4h
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


%% ------------------------------------------------------------
% 每天6行，共2004行
%
% result2模板：
%
% A 日期
% B 时间段
% C 充电量
% D 放电量
% E 时刻
% F 储电量
%% ------------------------------------------------------------

nCDRow = ...
    nDay*nBlock;


cdOut = ...
    cell(nCDRow,6);


r = ...
    1;


for d = 1:nDay

    for b = 1:nBlock

        %% 日期
        if b==1

            cdOut{r,1} = ...
                datestr( ...
                predDates(d), ...
                'yyyy-mm-dd');

        else

            cdOut{r,1} = ...
                '';

        end


        %% 时间段
        cdOut{r,2} = ...
            timeBlockName{b};


        %% 充电量
        cdOut{r,3} = ...
            charge4h(d,b);


        %% 放电量
        cdOut{r,4} = ...
            discharge4h(d,b);


        %% -----------------------------------------------
        % 每天第一行记录0:00 SOC
        % 每天第二行记录24:00 SOC
        %% -----------------------------------------------

        if b==1

            cdOut{r,5} = ...
                '0:00';


            cdOut{r,6} = ...
                SOCstart(d);


        elseif b==2

            cdOut{r,5} = ...
                '24:00';


            cdOut{r,6} = ...
                SOCend(d);


        else

            cdOut{r,5} = ...
                '';


            cdOut{r,6} = ...
                [];

        end


        r = ...
            r+1;

    end

end


%% ------------------------------------------------------------
% 直接从A2开始写
%% ------------------------------------------------------------

writecell( ...
    cdOut, ...
    result2File, ...
    'Sheet','充放电量', ...
    'Range','A2');


fprintf( ...
    '充放电量写入完成，共%d行。\n', ...
    nCDRow);


%% ============================================================
% 16. 写result2：紧急购电量
%
% 同一天连续10min紧急购电合并。
%
% 没有紧急购电的日期也保留一行：
% 日期 + 空白时间段 + 空白购电量
%% ============================================================

emergencyRows = ...
    cell(0,3);


outRow = ...
    0;


for d = 1:nDay

    x = ...
        emergencyGrid(d,:);


    active = ...
        x>1e-8;


    %% --------------------------------------------------------
    % 当天无紧急购电
    %% --------------------------------------------------------

    if ~any(active)

        outRow = ...
            outRow+1;


        emergencyRows{outRow,1} = ...
            datestr( ...
            predDates(d), ...
            'yyyy-mm-dd');


        emergencyRows{outRow,2} = ...
            '';


        emergencyRows{outRow,3} = ...
            [];


        continue;

    end


    %% --------------------------------------------------------
    % 找连续紧急购电区间
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

        s = ...
            starts(k);


        e = ...
            ends(k);


        outRow = ...
            outRow+1;


        %% 该日第一条写日期
        if k==1

            emergencyRows{outRow,1} = ...
                datestr( ...
                predDates(d), ...
                'yyyy-mm-dd');

        else

            emergencyRows{outRow,1} = ...
                '';

        end


        %% 时间段
        emergencyRows{outRow,2} = ...
            makeEmergencyTimeRange( ...
            s,e);


        %% 区间总紧急购电量
        emergencyRows{outRow,3} = ...
            sum( ...
            x(s:e));

    end

end


%% ------------------------------------------------------------
% 先清掉模板中可能遗留的旧结果
%% ------------------------------------------------------------

clearEmergency = ...
    repmat( ...
    {''}, ...
    5000, ...
    3);


writecell( ...
    clearEmergency, ...
    result2File, ...
    'Sheet','紧急购电量', ...
    'Range','A2');


%% ------------------------------------------------------------
% 再写本次结果
%% ------------------------------------------------------------

writecell( ...
    emergencyRows, ...
    result2File, ...
    'Sheet','紧急购电量', ...
    'Range','A2');


fprintf( ...
    '紧急购电量写入完成，共%d行。\n', ...
    size(emergencyRows,1));


%% ============================================================
% 17. result2校验
%% ============================================================

fprintf('\n');
fprintf('====================================================\n');
fprintf(' 官方 result2.xlsx 写入完成\n');
fprintf('====================================================\n');


fprintf( ...
    '计划购电量：%.2f kWh\n', ...
    sum(planGrid,'all'));


fprintf( ...
    '计划购电费：%.2f 元\n', ...
    totalPlanCost);


fprintf( ...
    '紧急购电量：%.2f kWh\n', ...
    totalEmergencyEnergy);


fprintf( ...
    '紧急购电费：%.2f 元\n', ...
    totalEmergencyCost);


fprintf( ...
    '总费用：%.2f 元\n', ...
    totalCost);


fprintf( ...
    '实际充电量：%.2f kWh\n', ...
    totalCharge);


fprintf( ...
    '实际放电量：%.2f kWh\n', ...
    totalDischarge);


fprintf( ...
    '年末SOC：%.6f kWh\n', ...
    SOCend(end));


fprintf('\n官方文件：\n%s\n', ...
    result2File);


fprintf('====================================================\n');


%% ============================================================
% 18. 保存实验汇总文件
%% ============================================================

summaryTable = ...
    table( ...
    "P2Similar10CausalAffineLP", ...
    totalPlanEnergy, ...
    totalPlanCost, ...
    totalEmergencyEnergy, ...
    totalEmergencyCost, ...
    totalCost, ...
    totalActualSpill, ...
    totalCharge, ...
    totalDischarge, ...
    emergencyDays, ...
    emergencySlots, ...
    planSimultaneousSlots, ...
    actualSimultaneousSlots, ...
    SOCend(end), ...
    runtimeMinutes, ...
    'VariableNames',{ ...
    'Model', ...
    'PlanEnergy_kWh', ...
    'PlanCost_Yuan', ...
    'EmergencyEnergy_kWh', ...
    'EmergencyCost_Yuan', ...
    'TotalCost_Yuan', ...
    'ActualSpill_kWh', ...
    'ActualCharge_kWh', ...
    'ActualDischarge_kWh', ...
    'EmergencyDays', ...
    'EmergencySlots', ...
    'PlanSimultaneousSlots', ...
    'ActualSimultaneousSlots', ...
    'FinalSOC_kWh', ...
    'Runtime_Min'} ...
    );


dailyTable = ...
    table( ...
    predDates, ...
    SOCstart, ...
    SOCend, ...
    planCostDay, ...
    emergencyCostDay, ...
    totalCostDay, ...
    sum(planGrid,2), ...
    sum(emergencyGrid,2), ...
    sum(actualSpill,2), ...
    scenarioCount, ...
    meanSimilarDistance, ...
    'VariableNames',{ ...
    'Date', ...
    'SOCstart_kWh', ...
    'SOCend_kWh', ...
    'PlanCost_Yuan', ...
    'EmergencyCost_Yuan', ...
    'TotalCost_Yuan', ...
    'PlanEnergy_kWh', ...
    'EmergencyEnergy_kWh', ...
    'ActualSpill_kWh', ...
    'ScenarioCount', ...
    'MeanSimilarDistance'} ...
    );


if isfile(outXlsx)

    delete(outXlsx);

end


writetable( ...
    summaryTable, ...
    outXlsx, ...
    'Sheet','汇总');


writetable( ...
    dailyTable, ...
    outXlsx, ...
    'Sheet','每日结果');


save( ...
    outMat, ...
    'summaryTable', ...
    'dailyTable', ...
    'predDates', ...
    'predLoad', ...
    'predPV', ...
    'actualLoad', ...
    'actualPV', ...
    'forecastNet', ...
    'actualNet', ...
    'residualNet', ...
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
    'planCostDay', ...
    'emergencyCostDay', ...
    'totalCostDay', ...
    'totalCost', ...
    'cfg', ...
    'runtimeMinutes', ...
    '-v7.3');


fprintf('\n');
fprintf('实验结果另外保存为：\n');
fprintf('%s\n',outXlsx);
fprintf('%s\n',outMat);


%% ============================================================
% 局部函数1
%
% Similar10 因果仿射日前计划
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
% 功率 -> 每10min电量
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


%% 普通购电费
f(idxG) = ...
    price;


%% 期望5倍紧急购电成本
for s = 1:K

    f(idxEm(s,:)) = ...
        cfg.emergencyFactor ...
        *price/K;

end


%% ------------------------------------------------------------
% 期望储能吞吐量极小惩罚
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
%
% 包含零残差基础路径
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


%% ------------------------------------------------------------
% 基础预测路径供需平衡 + SOC
%% ------------------------------------------------------------

for t = 1:N

    %% 供需平衡
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


    %% SOC
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


%% 基础路径日初SOC
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
% 每个Similar10残差情景
%% ============================================================

for s = 1:K

    for t = 1:N

        %% ----------------------------------------------------
        % 电量平衡
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
% 不等式：
%
% 每个情景下仿射响应后的充放电量：
%
% 0 <= C <= Wmax
% 0 <= D <= Wmax
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


%% 基础充放电
ub(idxC0) = ...
    cfg.Wmax;


ub(idxD0) = ...
    cfg.Wmax;


%% 仿射系数
ub([
    idxACP
    idxACN
    idxADP
    idxADN
    ]) = ...
    1;


%% 基础SOC
lb(idxEbase) = ...
    cfg.Emin;


ub(idxEbase) = ...
    cfg.Emax;


%% 情景SOC
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
        'Causal affine plan failed：%s', ...
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
% 真实数据逐10min因果回放
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
    Pload(:) ...
    *cfg.dt;


Wpv = ...
    Pv(:) ...
    *cfg.dt;


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


    %% --------------------------------------------------------
    % 首先执行基础储能轨迹
    %% --------------------------------------------------------

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
    % SOC下越界：
    % 先减少放电
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
    % SOC上越界：
    % 先减少充电
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
    % 实际供需残差
    %
    % >0 表示缺电
    % <0 表示富余
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


        %% 剩余缺口 -> 紧急购电

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


        %% 剩余 -> 富余/未利用
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
            || E(t+1)>cfg.Emax+1e-6

        error( ...
            '实际SOC越界：t=%d，SOC=%.9f', ...
            t, ...
            E(t+1));

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
% TIMEFIX紧急购电连续时段
%
% slot s 对应：
%
% 10*(s-1) min -> 10*s min
%
% 例如：
% s=1 -> 0:00-0:10
% s=37 -> 6:00-6:10
%% ============================================================

function txt = makeEmergencyTimeRange(s,e)


startMinute = ...
    10*(s-1);


endMinute = ...
    10*e;


txt = ...
    sprintf( ...
    '%s-%s', ...
    formatResult2Time(startMinute), ...
    formatResult2Time(endMinute));

end


%% ============================================================
% 局部函数4
% 分钟 -> result2时间文字
%% ============================================================

function txt = formatResult2Time(totalMinute)


dayAdd = ...
    floor(totalMinute/1440);


minuteOfDay = ...
    mod(totalMinute,1440);


hh = ...
    floor(minuteOfDay/60);


mm = ...
    mod(minuteOfDay,60);


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