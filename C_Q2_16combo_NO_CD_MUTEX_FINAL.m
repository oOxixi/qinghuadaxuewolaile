%% ============================================================
% 2026 C题 问题2
%
% 16组预测模型最终热力图
%
% 4种负载预测 × 4种光伏预测
%
% 1. AS-Ridge
% 2. QAR
% 3. Q-Ridge
% 4. AS-SARIMA
%
% ============================================================
%
% 本版本严格采用：
%
% V2
% = 严格因果实际回放
% + 30日净负荷历史残差Q0.8经济风险校准
% + 取消充放电互斥约束
%
% ============================================================
%
% 与之前16组合版本最关键的不同：
%
% 1. cyclePenalty = 0
%
% 2. 计划阶段：
%       Wch >= 0
%       Wdis >= 0
%    允许二者同时 > 0
%
% 3. 实际阶段：
%    Wch、Wdis保留为两个独立变量
%    不再使用B的正负强制二选一
%
% 4. 仍然严格因果：
%    当前t的执行不读取未来actualLoad / actualPV
%
% 5. FORCE_FINAL_SOC_6000 = false
%
% ============================================================

clear;
clc;
close all;


fprintf('====================================================\n');
fprintf(' C题问题2：16组合热力图\n');
fprintf(' Q0.8 + 因果回放 + 允许同时充放电\n');
fprintf('====================================================\n\n');


%% ============================================================
% 0. 参数开关
%% ============================================================

FORCE_FINAL_SOC_6000 = false;


Q_LEVEL = ...
    0.80;


ROLLING_WINDOW_DAYS = ...
    30;


MIN_HISTORY_DAYS = ...
    7;


%% ============================================================
% 1. 四种模型顺序
%
% 行：负载
% 列：光伏
%% ============================================================

modelNames = [
    "AS-Ridge"
    "QAR"
    "Q-Ridge"
    "AS-SARIMA"
    ];


nModel = ...
    4;


nCombo = ...
    16;


%% ============================================================
% 2. 文件路径
%% ============================================================

baseDir = ...
    'E:\数模\2026年正式比赛\CUMCM2026Problems\C题\附件';


%% ------------------------------------------------------------
% 四模型预测缓存
%
% 要求：
%
% predLoad：334×144×4
% predPV：334×144×4
%% ------------------------------------------------------------

prediction4File = ...
    fullfile( ...
    baseDir, ...
    'Q2_4models_ASR_QAR_QRidge_ASSARIMA_predictions.mat');


%% ------------------------------------------------------------
% 原QAR+AS-Ridge预测文件
%
% 主要用于读取actualLoad、actualPV、predDates
%% ------------------------------------------------------------

basePredictionFile = ...
    fullfile( ...
    baseDir, ...
    'Q2_QAR_ASRidge_predictions.mat');


priceFile = ...
    fullfile( ...
    baseDir, ...
    '附件1.xlsx');


resultExcel = ...
    fullfile( ...
    baseDir, ...
    'Q2_16combo_NO_CD_MUTEX_FINAL.xlsx');


resultMat = ...
    fullfile( ...
    baseDir, ...
    'Q2_16combo_NO_CD_MUTEX_FINAL.mat');


%% ============================================================
% 3. 文件检查
%% ============================================================

if ~isfile(prediction4File)

    error( ...
        ['找不到四模型预测文件：\n%s\n\n', ...
        '先确认之前四模型预测缓存是否还在。'], ...
        prediction4File);

end


if ~isfile(basePredictionFile)

    error( ...
        '找不到基础预测文件：\n%s', ...
        basePredictionFile);

end


if ~isfile(priceFile)

    error( ...
        '找不到附件1：\n%s', ...
        priceFile);

end


%% ============================================================
% 4. 读取四模型预测
%% ============================================================

P = ...
    load(prediction4File);


if ~isfield(P,'predLoad') ...
        || ...
        ~isfield(P,'predPV')

    error( ...
        '四模型MAT必须包含predLoad和predPV');

end


predLoad4 = ...
    P.predLoad;


predPV4 = ...
    P.predPV;


if ~isequal( ...
        size(predLoad4), ...
        [334,144,4])

    error( ...
        ['predLoad尺寸错误。\n', ...
        '应为334×144×4，目前为%s'], ...
        mat2str(size(predLoad4)));

end


if ~isequal( ...
        size(predPV4), ...
        [334,144,4])

    error( ...
        ['predPV尺寸错误。\n', ...
        '应为334×144×4，目前为%s'], ...
        mat2str(size(predPV4)));

end


fprintf('四模型预测读取成功。\n');


%% ============================================================
% 5. 读取真实数据
%% ============================================================

S = ...
    load(basePredictionFile);


requiredVariables = {
    'actualLoad'
    'actualPV'
    };


for i = 1:length(requiredVariables)

    if ~isfield(S,requiredVariables{i})

        error( ...
            '基础MAT缺少变量：%s', ...
            requiredVariables{i});

    end

end


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
    size(actualLoad);


if nDay~=334 ...
        || ...
        nTime~=144

    error( ...
        '实际数据应为334×144');

end


%% ============================================================
% 6. 电价
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

    error('电价不是144个时段');

end


%% ============================================================
% 7. 时间轴
%
% 继续严格沿用当前V2逻辑：
%
% 原：
% 00:10 ... 23:50 00:00(+1)
%
% 内部：
% 00:00 00:10 ... 23:50
%% ============================================================

idx = ...
    [144,1:143];


price = ...
    [ ...
    priceRaw(end);
    priceRaw(1:end-1)
    ];


actualLoadRun = ...
    actualLoad(:,idx);


actualPVRun = ...
    actualPV(:,idx);


predLoadRun = ...
    predLoad4(:,idx,:);


predPVRun = ...
    predPV4(:,idx,:);


%% ============================================================
% 8. 储能参数
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


emergencyFactor = ...
    5;


%% ============================================================
% ★本版本关键
%
% 完全取消充放电惩罚
%% ============================================================

cyclePenalty = ...
    0;


%% ------------------------------------------------------------
% 弃光微小择优项仍保留
%% ------------------------------------------------------------

curtailPenalty = ...
    1e-5;


fprintf('\n');

fprintf('dt = %.6f h\n',dt);

fprintf('Wmax = %.6f kWh / 10min\n',Wmax);

fprintf('SOC范围 = %.0f ~ %.0f kWh\n', ...
    Emin,Emax);

fprintf('cyclePenalty = %.1e\n', ...
    cyclePenalty);

fprintf('允许同时充放电：是\n');

fprintf('强制年末6000：%s\n\n', ...
    yesno(FORCE_FINAL_SOC_6000));


%% ============================================================
% 9. LP设置
%% ============================================================

lpOptions = ...
    optimoptions( ...
    'linprog', ...
    'Algorithm','dual-simplex-highs', ...
    'Display','none');


%% ============================================================
% 10. 真实净负荷
%% ============================================================

actualNet = ...
    actualLoadRun ...
    - actualPVRun;


%% ============================================================
% 11. 结果初始化
%% ============================================================

costMatrix = ...
    zeros(4,4);


planCostMatrix = ...
    zeros(4,4);


emergencyCostMatrix = ...
    zeros(4,4);


planEnergyMatrix = ...
    zeros(4,4);


emergencyEnergyMatrix = ...
    zeros(4,4);


spillMatrix = ...
    zeros(4,4);


planCurtailMatrix = ...
    zeros(4,4);


chargeMatrix = ...
    zeros(4,4);


dischargeMatrix = ...
    zeros(4,4);


finalSOCMatrix = ...
    zeros(4,4);


q80MeanMatrix = ...
    zeros(4,4);


planSimultaneousMatrix = ...
    zeros(4,4);


actualSimultaneousMatrix = ...
    zeros(4,4);


emergencyDaysMatrix = ...
    zeros(4,4);


emergencySlotsMatrix = ...
    zeros(4,4);


%% ============================================================
% 明细表
%% ============================================================

ComboID = ...
    zeros(16,1);


LoadModel = ...
    strings(16,1);


PVModel = ...
    strings(16,1);


PlanEnergy_kWh = ...
    zeros(16,1);


PlanCost_yuan = ...
    zeros(16,1);


EmergencyEnergy_kWh = ...
    zeros(16,1);


EmergencyCost_yuan = ...
    zeros(16,1);


TotalCost_yuan = ...
    zeros(16,1);


PlanCurtail_kWh = ...
    zeros(16,1);


ActualSpill_kWh = ...
    zeros(16,1);


ActualCharge_kWh = ...
    zeros(16,1);


ActualDischarge_kWh = ...
    zeros(16,1);


EmergencyDays = ...
    zeros(16,1);


EmergencySlots = ...
    zeros(16,1);


MeanSOCend_kWh = ...
    zeros(16,1);


MinSOCend_kWh = ...
    zeros(16,1);


MaxSOCend_kWh = ...
    zeros(16,1);


FinalSOC_kWh = ...
    zeros(16,1);


Q80Mean_kW = ...
    zeros(16,1);


Q80Min_kW = ...
    zeros(16,1);


Q80Max_kW = ...
    zeros(16,1);


PlanSimultaneousSlots = ...
    zeros(16,1);


ActualSimultaneousSlots = ...
    zeros(16,1);


RawNetBias_kW = ...
    zeros(16,1);


RawNetMAE_kW = ...
    zeros(16,1);


CorrectedNetBias_kW = ...
    zeros(16,1);


CorrectedNetMAE_kW = ...
    zeros(16,1);


%% ============================================================
% 12. 16种组合
%% ============================================================

combo = ...
    0;


timerAll = ...
    tic;


for iLoad = 1:4


    for iPV = 1:4


        combo = ...
            combo+1;


        fprintf('\n');
        fprintf('####################################################\n');
        fprintf('组合 %02d / 16\n',combo);
        fprintf('负载：%s\n',modelNames(iLoad));
        fprintf('光伏：%s\n',modelNames(iPV));
        fprintf('####################################################\n');


        %% ====================================================
        % 12.1 原始预测
        %% ====================================================

        predLoadCurrent = ...
            predLoadRun(:,:,iLoad);


        predPVCurrent = ...
            predPVRun(:,:,iPV);


        forecastNet = ...
            predLoadCurrent ...
            - predPVCurrent;


        %% ====================================================
        % 12.2 原始净负荷误差
        %
        % Bias = prediction - actual
        %% ====================================================

        rawError = ...
            forecastNet ...
            - actualNet;


        RawNetBias_kW(combo) = ...
            mean( ...
            rawError, ...
            'all');


        RawNetMAE_kW(combo) = ...
            mean( ...
            abs(rawError), ...
            'all');


        %% ====================================================
        % 12.3 历史残差
        %
        % residualNet =
        % actual - forecast
        %% ====================================================

        residualNet = ...
            actualNet ...
            - forecastNet;


        %% ====================================================
        % 12.4 严格因果Q0.8
        %% ====================================================

        q80Correction = ...
            zeros(nDay,nTime);


        calibrationActive = ...
            false(nDay,1);


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


        %% ====================================================
        % 12.5 Q0.8修正
        %% ====================================================

        correctedNet = ...
            forecastNet ...
            + q80Correction;


        correctedLoad = ...
            correctedNet ...
            + predPVCurrent;


        correctedLoad = ...
            max( ...
            correctedLoad, ...
            0);


        %% ====================================================
        % 12.6 校准后误差
        %% ====================================================

        corrError = ...
            correctedNet ...
            - actualNet;


        CorrectedNetBias_kW(combo) = ...
            mean( ...
            corrError, ...
            'all');


        CorrectedNetMAE_kW(combo) = ...
            mean( ...
            abs(corrError), ...
            'all');


        activeMask = ...
            repmat( ...
            calibrationActive, ...
            1, ...
            nTime);


        qUse = ...
            q80Correction(activeMask);


        if isempty(qUse)


            qMean = ...
                0;


            qMin = ...
                0;


            qMax = ...
                0;


        else


            qMean = ...
                mean(qUse);


            qMin = ...
                min(qUse);


            qMax = ...
                max(qUse);


        end


        %% ====================================================
        % 12.7 当前组合初始化
        %% ====================================================

        planGrid = ...
            zeros(nDay,nTime);


        planCharge = ...
            zeros(nDay,nTime);


        planDischarge = ...
            zeros(nDay,nTime);


        planCurtail = ...
            zeros(nDay,nTime);


        actualCharge = ...
            zeros(nDay,nTime);


        actualDischarge = ...
            zeros(nDay,nTime);


        actualSpill = ...
            zeros(nDay,nTime);


        emergencyGrid = ...
            zeros(nDay,nTime);


        SOCend = ...
            zeros(nDay,1);


        planCostDay = ...
            zeros(nDay,1);


        emergencyCostDay = ...
            zeros(nDay,1);


        Ecurrent = ...
            Einitial;


        %% ====================================================
        % 12.8 全年逐日
        %% ====================================================

        for d = 1:nDay


            isLastDay = ...
                (d==nDay);


            EdayStart = ...
                Ecurrent;


            %% ----------------------------------------------
            % 日末约束
            %% ----------------------------------------------

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


            %% ==============================================
            % 0:00计划LP
            %
            % 允许同时充放电
            %% ==============================================

            plan = ...
                solveDailyPlanTerminalSOC( ...
                correctedLoad(d,:)', ...
                predPVCurrent(d,:)', ...
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


            planCostDay(d) = ...
                sum( ...
                price ...
                .* plan.Wgrid);


            %% ==============================================
            % 严格因果实际回放
            %
            % 同样允许同时充放电
            %% ==============================================

            replay = ...
                replayActualDayCausalAllowSimultaneous( ...
                actualLoadRun(d,:)', ...
                actualPVRun(d,:)', ...
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


            Ecurrent = ...
                replay.Eend;


            SOCend(d) = ...
                Ecurrent;


            emergencyCostDay(d) = ...
                sum( ...
                emergencyFactor ...
                .* price ...
                .* replay.Wem);


        end


        %% ====================================================
        % 12.9 当前组合统计
        %% ====================================================

        totalPlanEnergy = ...
            sum( ...
            planGrid, ...
            'all');


        totalPlanCost = ...
            sum( ...
            planCostDay);


        totalEmergencyEnergy = ...
            sum( ...
            emergencyGrid, ...
            'all');


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


        %% ====================================================
        % 同时充放电统计
        %% ====================================================

        planSimMask = ...
            planCharge>1e-8 ...
            & ...
            planDischarge>1e-8;


        actualSimMask = ...
            actualCharge>1e-8 ...
            & ...
            actualDischarge>1e-8;


        nPlanSim = ...
            nnz(planSimMask);


        nActualSim = ...
            nnz(actualSimMask);


        %% ====================================================
        % 12.10 写矩阵
        %% ====================================================

        costMatrix(iLoad,iPV) = ...
            totalCost;


        planCostMatrix(iLoad,iPV) = ...
            totalPlanCost;


        emergencyCostMatrix(iLoad,iPV) = ...
            totalEmergencyCost;


        planEnergyMatrix(iLoad,iPV) = ...
            totalPlanEnergy;


        emergencyEnergyMatrix(iLoad,iPV) = ...
            totalEmergencyEnergy;


        spillMatrix(iLoad,iPV) = ...
            totalActualSpill;


        planCurtailMatrix(iLoad,iPV) = ...
            totalPlanCurtail;


        chargeMatrix(iLoad,iPV) = ...
            totalCharge;


        dischargeMatrix(iLoad,iPV) = ...
            totalDischarge;


        finalSOCMatrix(iLoad,iPV) = ...
            SOCend(end);


        q80MeanMatrix(iLoad,iPV) = ...
            qMean;


        planSimultaneousMatrix(iLoad,iPV) = ...
            nPlanSim;


        actualSimultaneousMatrix(iLoad,iPV) = ...
            nActualSim;


        emergencyDaysMatrix(iLoad,iPV) = ...
            emergencyDays;


        emergencySlotsMatrix(iLoad,iPV) = ...
            emergencySlots;


        %% ====================================================
        % 12.11 写明细
        %% ====================================================

        ComboID(combo) = ...
            combo;


        LoadModel(combo) = ...
            modelNames(iLoad);


        PVModel(combo) = ...
            modelNames(iPV);


        PlanEnergy_kWh(combo) = ...
            totalPlanEnergy;


        PlanCost_yuan(combo) = ...
            totalPlanCost;


        EmergencyEnergy_kWh(combo) = ...
            totalEmergencyEnergy;


        EmergencyCost_yuan(combo) = ...
            totalEmergencyCost;


        TotalCost_yuan(combo) = ...
            totalCost;


        PlanCurtail_kWh(combo) = ...
            totalPlanCurtail;


        ActualSpill_kWh(combo) = ...
            totalActualSpill;


        ActualCharge_kWh(combo) = ...
            totalCharge;


        ActualDischarge_kWh(combo) = ...
            totalDischarge;


        EmergencyDays(combo) = ...
            emergencyDays;


        EmergencySlots(combo) = ...
            emergencySlots;


        MeanSOCend_kWh(combo) = ...
            mean(SOCend);


        MinSOCend_kWh(combo) = ...
            min(SOCend);


        MaxSOCend_kWh(combo) = ...
            max(SOCend);


        FinalSOC_kWh(combo) = ...
            SOCend(end);


        Q80Mean_kW(combo) = ...
            qMean;


        Q80Min_kW(combo) = ...
            qMin;


        Q80Max_kW(combo) = ...
            qMax;


        PlanSimultaneousSlots(combo) = ...
            nPlanSim;


        ActualSimultaneousSlots(combo) = ...
            nActualSim;


        %% ====================================================
        % 12.12 当前组合输出
        %% ====================================================

        fprintf('\n');

        fprintf('计划购电量：%.2f kWh\n', ...
            totalPlanEnergy);

        fprintf('计划购电费：%.2f 元\n', ...
            totalPlanCost);

        fprintf('紧急购电量：%.2f kWh\n', ...
            totalEmergencyEnergy);

        fprintf('紧急购电费：%.2f 元\n', ...
            totalEmergencyCost);

        fprintf('总成本：%.2f 元\n', ...
            totalCost);

        fprintf('actualSpill：%.2f kWh\n', ...
            totalActualSpill);

        fprintf('计划同时充放电时段：%d\n', ...
            nPlanSim);

        fprintf('实际同时充放电时段：%d\n', ...
            nActualSim);

        fprintf('最终SOC：%.2f kWh\n', ...
            SOCend(end));


    end


end


runtime = ...
    toc(timerAll);


%% ============================================================
% 13. 汇总表
%% ============================================================

summaryTable = ...
    table( ...
    ComboID, ...
    LoadModel, ...
    PVModel, ...
    RawNetBias_kW, ...
    RawNetMAE_kW, ...
    CorrectedNetBias_kW, ...
    CorrectedNetMAE_kW, ...
    Q80Mean_kW, ...
    Q80Min_kW, ...
    Q80Max_kW, ...
    PlanEnergy_kWh, ...
    PlanCost_yuan, ...
    EmergencyEnergy_kWh, ...
    EmergencyCost_yuan, ...
    TotalCost_yuan, ...
    PlanCurtail_kWh, ...
    ActualSpill_kWh, ...
    ActualCharge_kWh, ...
    ActualDischarge_kWh, ...
    EmergencyDays, ...
    EmergencySlots, ...
    MeanSOCend_kWh, ...
    MinSOCend_kWh, ...
    MaxSOCend_kWh, ...
    FinalSOC_kWh, ...
    PlanSimultaneousSlots, ...
    ActualSimultaneousSlots);


summaryByCost = ...
    sortrows( ...
    summaryTable, ...
    'TotalCost_yuan', ...
    'ascend');


fprintf('\n');
fprintf('====================================================\n');
fprintf(' 16种组合全年总成本排名\n');
fprintf('====================================================\n');


disp( ...
    summaryByCost(:,{ ...
    'ComboID', ...
    'LoadModel', ...
    'PVModel', ...
    'PlanCost_yuan', ...
    'EmergencyCost_yuan', ...
    'TotalCost_yuan', ...
    'ActualSpill_kWh', ...
    'PlanSimultaneousSlots', ...
    'ActualSimultaneousSlots'}));


%% ============================================================
% 14. 最优组合
%% ============================================================

[bestCost,bestID] = ...
    min(TotalCost_yuan);


fprintf('\n');
fprintf('====================================================\n');
fprintf(' 最优组合\n');
fprintf('====================================================\n');


fprintf('负载：%s\n', ...
    LoadModel(bestID));


fprintf('光伏：%s\n', ...
    PVModel(bestID));


fprintf('全年总成本：%.2f 元\n', ...
    bestCost);


fprintf('计划购电费：%.2f 元\n', ...
    PlanCost_yuan(bestID));


fprintf('紧急购电费：%.2f 元\n', ...
    EmergencyCost_yuan(bestID));


fprintf('紧急购电量：%.2f kWh\n', ...
    EmergencyEnergy_kWh(bestID));


fprintf('actualSpill：%.2f kWh\n', ...
    ActualSpill_kWh(bestID));


fprintf('计划同时充放电时段：%d\n', ...
    PlanSimultaneousSlots(bestID));


fprintf('实际同时充放电时段：%d\n', ...
    ActualSimultaneousSlots(bestID));


fprintf('====================================================\n');


%% ============================================================
% 15. ★最终总成本热力图
%% ============================================================

figure( ...
    'Color','w', ...
    'Position',[200 120 900 700]);


imagesc( ...
    costMatrix);


colorbar;


xticks(1:4);

yticks(1:4);


xticklabels(modelNames);

yticklabels(modelNames);


xlabel( ...
    '光伏预测模型', ...
    'FontSize',12);


ylabel( ...
    '负载预测模型', ...
    'FontSize',12);


title( ...
    '16种组合全年总购电成本 / 元', ...
    'FontSize',14);


for i = 1:4


    for j = 1:4


        text( ...
            j, ...
            i, ...
            sprintf( ...
            '%.0f', ...
            costMatrix(i,j)), ...
            'HorizontalAlignment','center', ...
            'VerticalAlignment','middle', ...
            'FontWeight','bold', ...
            'FontSize',10);


    end


end


%% ============================================================
% 16. 紧急购电量热力图
%% ============================================================

figure( ...
    'Color','w', ...
    'Position',[200 120 900 700]);


imagesc( ...
    emergencyEnergyMatrix);


colorbar;


xticks(1:4);

yticks(1:4);


xticklabels(modelNames);

yticklabels(modelNames);


xlabel('光伏预测模型');

ylabel('负载预测模型');


title( ...
    '16种组合全年紧急购电量 / kWh');


for i = 1:4


    for j = 1:4


        text( ...
            j,i, ...
            sprintf( ...
            '%.0f', ...
            emergencyEnergyMatrix(i,j)), ...
            'HorizontalAlignment','center', ...
            'FontWeight','bold');


    end


end


%% ============================================================
% 17. actualSpill热力图
%% ============================================================

figure( ...
    'Color','w', ...
    'Position',[200 120 900 700]);


imagesc( ...
    spillMatrix);


colorbar;


xticks(1:4);

yticks(1:4);


xticklabels(modelNames);

yticklabels(modelNames);


xlabel('光伏预测模型');

ylabel('负载预测模型');


title( ...
    '16种组合全年actualSpill / kWh');


for i = 1:4


    for j = 1:4


        text( ...
            j,i, ...
            sprintf( ...
            '%.0f', ...
            spillMatrix(i,j)), ...
            'HorizontalAlignment','center', ...
            'FontWeight','bold');


    end


end


%% ============================================================
% 18. 计划同时充放电次数热力图
%% ============================================================

figure( ...
    'Color','w', ...
    'Position',[200 120 900 700]);


imagesc( ...
    planSimultaneousMatrix);


colorbar;


xticks(1:4);

yticks(1:4);


xticklabels(modelNames);

yticklabels(modelNames);


xlabel('光伏预测模型');

ylabel('负载预测模型');


title( ...
    '16种组合：计划阶段同时充放电时段数');


for i = 1:4


    for j = 1:4


        text( ...
            j,i, ...
            sprintf( ...
            '%d', ...
            planSimultaneousMatrix(i,j)), ...
            'HorizontalAlignment','center', ...
            'FontWeight','bold');


    end


end


%% ============================================================
% 19. 实际同时充放电次数热力图
%% ============================================================

figure( ...
    'Color','w', ...
    'Position',[200 120 900 700]);


imagesc( ...
    actualSimultaneousMatrix);


colorbar;


xticks(1:4);

yticks(1:4);


xticklabels(modelNames);

yticklabels(modelNames);


xlabel('光伏预测模型');

ylabel('负载预测模型');


title( ...
    '16种组合：实际阶段同时充放电时段数');


for i = 1:4


    for j = 1:4


        text( ...
            j,i, ...
            sprintf( ...
            '%d', ...
            actualSimultaneousMatrix(i,j)), ...
            'HorizontalAlignment','center', ...
            'FontWeight','bold');


    end


end


%% ============================================================
% 20. 写Excel
%% ============================================================

if isfile(resultExcel)

    delete(resultExcel);

end


writetable( ...
    summaryTable, ...
    resultExcel, ...
    'Sheet','16组合结果');


writetable( ...
    summaryByCost, ...
    resultExcel, ...
    'Sheet','总成本排名');


writeMatrixSheet( ...
    resultExcel, ...
    '总成本矩阵', ...
    modelNames, ...
    costMatrix);


writeMatrixSheet( ...
    resultExcel, ...
    '计划购电费矩阵', ...
    modelNames, ...
    planCostMatrix);


writeMatrixSheet( ...
    resultExcel, ...
    '紧急购电费矩阵', ...
    modelNames, ...
    emergencyCostMatrix);


writeMatrixSheet( ...
    resultExcel, ...
    '紧急购电量矩阵', ...
    modelNames, ...
    emergencyEnergyMatrix);


writeMatrixSheet( ...
    resultExcel, ...
    'actualSpill矩阵', ...
    modelNames, ...
    spillMatrix);


writeMatrixSheet( ...
    resultExcel, ...
    '计划同时充放电', ...
    modelNames, ...
    planSimultaneousMatrix);


writeMatrixSheet( ...
    resultExcel, ...
    '实际同时充放电', ...
    modelNames, ...
    actualSimultaneousMatrix);


%% ============================================================
% 21. 保存MAT
%% ============================================================

save( ...
    resultMat, ...
    'modelNames', ...
    'costMatrix', ...
    'planCostMatrix', ...
    'emergencyCostMatrix', ...
    'planEnergyMatrix', ...
    'emergencyEnergyMatrix', ...
    'spillMatrix', ...
    'planCurtailMatrix', ...
    'chargeMatrix', ...
    'dischargeMatrix', ...
    'finalSOCMatrix', ...
    'q80MeanMatrix', ...
    'planSimultaneousMatrix', ...
    'actualSimultaneousMatrix', ...
    'emergencyDaysMatrix', ...
    'emergencySlotsMatrix', ...
    'summaryTable', ...
    'summaryByCost', ...
    'FORCE_FINAL_SOC_6000', ...
    'Q_LEVEL', ...
    'ROLLING_WINDOW_DAYS', ...
    'MIN_HISTORY_DAYS', ...
    'cyclePenalty', ...
    'curtailPenalty', ...
    '-v7.3');


fprintf('\n');
fprintf('====================================================\n');
fprintf(' 16组合全部完成\n');
fprintf('====================================================\n');


fprintf('运行时间：%.2f min\n', ...
    runtime/60);


fprintf('\nExcel：\n%s\n', ...
    resultExcel);


fprintf('\nMAT：\n%s\n', ...
    resultMat);


fprintf('====================================================\n');


%% ============================================================
% ============================================================
% 局部函数1
%
% 日前计划LP
%
% ★允许同时充放电
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
% 目标函数
%% ============================================================

f = ...
    zeros(nvar,1);


f(idxGrid) = ...
    price;


%% cyclePenalty = 0

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


%% ============================================================
% 供需平衡
%% ============================================================

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


%% ============================================================
% SOC动态
%% ============================================================

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


%% 单独限制充电

ub(idxCh) = ...
    Wmax;


%% 单独限制放电

ub(idxDis) = ...
    Wmax;


%% 没有充放电互斥约束


%% 计划弃光

ub(idxCut) = ...
    Wpv;


%% SOC

lb(idxE) = ...
    Emin;


ub(idxE) = ...
    Emax;


lb(idxE(end)) = ...
    terminalLow;


ub(idxE(end)) = ...
    terminalHigh;


%% ============================================================
% linprog
%% ============================================================

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
% 局部函数2
%
% 严格因果实际回放
%
% ★允许同时充放电
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


E = ...
    zeros(N+1,1);


E(1) = ...
    Estart;


for t = 1:N


    Ecurrent = ...
        E(t);


    %% ========================================================
    % 下一时刻SOC允许区间
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


        EnextLow = ...
            max( ...
            Emin, ...
            EfinalTarget ...
            -remainingSlots ...
            *eta_ch ...
            *Wmax);


        EnextHigh = ...
            min( ...
            Emax, ...
            EfinalTarget ...
            +remainingSlots ...
            *Wmax/eta_dis);


    end


    %% ========================================================
    % 先执行0:00计划
    %
    % 两个独立变量
    %% ========================================================

    WchNow = ...
        min( ...
        max( ...
        WchPlan(t), ...
        0), ...
        Wmax);


    WdisNow = ...
        min( ...
        max( ...
        WdisPlan(t), ...
        0), ...
        Wmax);


    %% ========================================================
    % 按SOC修正计划动作
    %% ========================================================

    Enew = ...
        Ecurrent ...
        +eta_ch*WchNow ...
        -WdisNow/eta_dis;


    %% --------------------------------------------------------
    % SOC过低：
    %
    % 先减少放电
    % 再增加充电
    %% --------------------------------------------------------

    if Enew<EnextLow


        need = ...
            EnextLow-Enew;


        reduceDis = ...
            min( ...
            WdisNow, ...
            need*eta_dis);


        WdisNow = ...
            WdisNow-reduceDis;


        Enew = ...
            Ecurrent ...
            +eta_ch*WchNow ...
            -WdisNow/eta_dis;


        if Enew<EnextLow-1e-10


            addCh = ...
                min( ...
                Wmax-WchNow, ...
                (EnextLow-Enew)/eta_ch);


            WchNow = ...
                WchNow+addCh;


            Enew = ...
                Ecurrent ...
                +eta_ch*WchNow ...
                -WdisNow/eta_dis;


        end


    end


    %% --------------------------------------------------------
    % SOC过高：
    %
    % 先减少充电
    % 再增加放电
    %% --------------------------------------------------------

    if Enew>EnextHigh


        need = ...
            Enew-EnextHigh;


        reduceCh = ...
            min( ...
            WchNow, ...
            need/eta_ch);


        WchNow = ...
            WchNow-reduceCh;


        Enew = ...
            Ecurrent ...
            +eta_ch*WchNow ...
            -WdisNow/eta_dis;


        if Enew>EnextHigh+1e-10


            addDis = ...
                min( ...
                Wmax-WdisNow, ...
                (Enew-EnextHigh)*eta_dis);


            WdisNow = ...
                WdisNow+addDis;


            Enew = ...
                Ecurrent ...
                +eta_ch*WchNow ...
                -WdisNow/eta_dis;


        end


    end


    %% ========================================================
    % 当前真实供需差
    %
    % 正数：缺电
    % 负数：富余
    %% ========================================================

    residual = ...
        Wload(t) ...
        +WchNow ...
        -Wpv(t) ...
        -Wgrid(t) ...
        -WdisNow;


    %% ========================================================
    % 当前缺电
    %% ========================================================

    if residual>0


        %% ----------------------------------------------------
        % 第一步：减少充电
        %% ----------------------------------------------------

        maxReduceChargeSOC = ...
            max( ...
            (Enew-EnextLow)/eta_ch, ...
            0);


        reduceCharge = ...
            min([ ...
            residual, ...
            WchNow, ...
            maxReduceChargeSOC]);


        WchNow = ...
            WchNow-reduceCharge;


        residual = ...
            residual-reduceCharge;


        Enew = ...
            Enew ...
            -eta_ch*reduceCharge;


        %% ----------------------------------------------------
        % 第二步：增加放电
        %% ----------------------------------------------------

        if residual>1e-12


            maxDisSOC = ...
                eta_dis ...
                *max( ...
                Enew-EnextLow, ...
                0);


            extraDis = ...
                min([ ...
                residual, ...
                Wmax-WdisNow, ...
                maxDisSOC]);


            WdisNow = ...
                WdisNow+extraDis;


            residual = ...
                residual-extraDis;


            Enew = ...
                Enew ...
                -extraDis/eta_dis;


        end


        %% ----------------------------------------------------
        % 第三步：紧急购电
        %% ----------------------------------------------------

        Wem(t) = ...
            max( ...
            residual, ...
            0);


        Wspill(t) = ...
            0;


    %% ========================================================
    % 当前富余
    %% ========================================================

    elseif residual<0


        surplus = ...
            -residual;


        %% ----------------------------------------------------
        % 第一步：减少放电
        %% ----------------------------------------------------

        maxReduceDisSOC = ...
            eta_dis ...
            *max( ...
            EnextHigh-Enew, ...
            0);


        reduceDis = ...
            min([ ...
            surplus, ...
            WdisNow, ...
            maxReduceDisSOC]);


        WdisNow = ...
            WdisNow-reduceDis;


        surplus = ...
            surplus-reduceDis;


        Enew = ...
            Enew ...
            +reduceDis/eta_dis;


        %% ----------------------------------------------------
        % 第二步：增加充电
        %% ----------------------------------------------------

        if surplus>1e-12


            maxChargeSOC = ...
                max( ...
                EnextHigh-Enew, ...
                0) ...
                /eta_ch;


            extraCh = ...
                min([ ...
                surplus, ...
                Wmax-WchNow, ...
                maxChargeSOC]);


            WchNow = ...
                WchNow+extraCh;


            surplus = ...
                surplus-extraCh;


            Enew = ...
                Enew ...
                +eta_ch*extraCh;


        end


        %% ----------------------------------------------------
        % 第三步：actualSpill
        %% ----------------------------------------------------

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


    E(t+1) = ...
        Ecurrent ...
        +eta_ch*Wch(t) ...
        -Wdis(t)/eta_dis;


    %% ========================================================
    % SOC检查
    %% ========================================================

    if E(t+1)<Emin-1e-6 ...
            || ...
            E(t+1)>Emax+1e-6

        error( ...
            '实际SOC越界：t=%d', ...
            t);

    end


    %% ========================================================
    % 功率检查
    %% ========================================================

    if Wch(t)>Wmax+1e-6 ...
            || ...
            Wdis(t)>Wmax+1e-6

        error( ...
            '实际充放电功率越界：t=%d', ...
            t);

    end


    %% ========================================================
    % 供需平衡检查
    %% ========================================================

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
            ['供需平衡失败：', ...
            't=%d,error=%.8f'], ...
            t, ...
            balanceError);

    end


end


if forceFinalSOC


    if abs(E(end)-EfinalTarget)>1e-4

        error( ...
            '最终SOC未达到6000');

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
% Excel矩阵输出
%% ============================================================

function writeMatrixSheet( ...
    excelFile, ...
    sheetName, ...
    modelNames, ...
    M)


out = ...
    cell(5,5);


out{1,1} = ...
    '负载\光伏';


for j = 1:4

    out{1,j+1} = ...
        char(modelNames(j));

end


for i = 1:4


    out{i+1,1} = ...
        char(modelNames(i));


    for j = 1:4

        out{i+1,j+1} = ...
            M(i,j);

    end


end


writecell( ...
    out, ...
    excelFile, ...
    'Sheet',sheetName, ...
    'Range','A1');


end


%% ============================================================
% 局部函数4：是/否
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