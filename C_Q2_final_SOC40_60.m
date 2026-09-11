%% ============================================================
% 2026 C题 问题2 最终版
%
% 预测模型：
%   负载：QAR，tau_L = 0.80
%   光伏：AS-Ridge，tau_PV = 0.20
%
% 储能最终规则：
%
% 1. 每天0:00：
%    使用当天真实日初SOC制定全天计划
%
% 2. SOC跨日连续：
%
%       E_actual(d+1,0) = E_actual(d,24)
%
% 3. 电池在任意时刻的储电量必须满足：
%
%       1200 <= E_t <= 10800 kWh
%
%    即12000 kWh额定容量的10%~90%
%
% 4. 2月1日~12月30日日末SOC：
%
%       1200 <= E_day_end <= 10800 kWh
%
%    即日末SOC同样允许位于10%~90%范围内
%
% 5. 12月31日24:00：
%
%       E_end = 6000 kWh
%
% 6. 计划阶段和实际运行阶段均执行上述SOC约束
%
% 7. 最终直接填写：
%
% E:\数模\2026年正式比赛\CUMCM2026Problems\C题\附件\
% 附件5\result2.xlsx
%
%% ============================================================

clear;
clc;
close all;


fprintf('====================================================\n');
fprintf(' C题问题2最终版：固定0.8/0.2 + 日末SOC 10%%~90%%\n');
fprintf(' 全过程SOC范围：10%%~90%%\n');
fprintf(' 12月31日最终SOC回到6000 kWh\n');
fprintf('====================================================\n\n');


%% ============================================================
% 1. 文件路径
%% ============================================================

baseDir = ...
    'E:\数模\2026年正式比赛\CUMCM2026Problems\C题\附件';


%% ------------------------------------------------------------
% 已经生成好的预测结果：
%
% 负载 QAR tau = 0.8
% 光伏 AS-Ridge tau = 0.2
%% ------------------------------------------------------------

predictionFile = ...
    fullfile( ...
    baseDir, ...
    'Q2_QAR_ASRidge_predictions.mat');


%% 电价

priceFile = ...
    fullfile( ...
    baseDir, ...
    '附件1.xlsx');


%% ------------------------------------------------------------
% ★直接填写官方result2
%% ------------------------------------------------------------

resultFile = ...
    fullfile( ...
    baseDir, ...
    '附件5', ...
    'result2.xlsx');


%% MAT详细结果

matFile = ...
    fullfile( ...
    baseDir, ...
    'Q2_final_SOC10_90.mat');


%% ============================================================
% 2. 文件检查
%% ============================================================

if ~isfile(predictionFile)

    error( ...
        '找不到预测结果：\n%s', ...
        predictionFile);

end


if ~isfile(priceFile)

    error( ...
        '找不到附件1：\n%s', ...
        priceFile);

end


if ~isfile(resultFile)

    error( ...
        '找不到result2：\n%s', ...
        resultFile);

end


fprintf('最终结果将直接写入：\n%s\n\n', ...
    resultFile);


%% ============================================================
% 3. 读取预测数据
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
            '预测MAT中缺少变量：%s', ...
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
        '预测结果应为334×144，目前为%d×%d', ...
        nDay,nTime);

end


fprintf( ...
    '数据读取完成：%d天 × %d个10min时段\n\n', ...
    nDay,nTime);


%% ============================================================
% 4. 读取电价
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

    error('附件1电价不是144个时段');

end


%% ============================================================
% 5. 时间轴转换
%
% 附件原始：
%
% 00:10
% 00:20
% ...
% 23:50
% 00:00(+1)
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


%% ============================================================
% 6. 固定风险参数
%
% 当前预测MAT本身已经是：
%
% 负载 tau = 0.8
% 光伏 tau = 0.2
%% ============================================================

tauLoad = ...
    0.80;


tauPV = ...
    0.20;


fprintf('固定预测风险参数：\n');

fprintf('tau_Load = %.2f\n',tauLoad);

fprintf('tau_PV   = %.2f\n\n',tauPV);


%% ============================================================
% 7. 储能参数
%% ============================================================

%% 单个时段为10min

dt = ...
    10/60;


%% 充放电效率

eta = ...
    0.90;


%% ============================================================
% 储能额定容量
%% ============================================================

Ecapacity = ...
    12000;


%% ============================================================
% ★全过程SOC物理范围：10%~90%
%% ============================================================

Emin = ...
    0.10*Ecapacity;

% = 1200 kWh


Emax = ...
    0.90*Ecapacity;

% = 10800 kWh


%% ============================================================
% ★普通日日末SOC范围：10%~90%
%% ============================================================

EdayMin = ...
    0.10*Ecapacity;

% = 1200 kWh


EdayMax = ...
    0.90*Ecapacity;

% = 10800 kWh


%% ============================================================
% ★12月31日最终SOC
%% ============================================================

EfinalTarget = ...
    6000;


%% ============================================================
% 最大充放电功率
%% ============================================================

Pmax = ...
    5000;


%% 10min最大充放电量

Wmax = ...
    Pmax*dt;


%% ------------------------------------------------------------
% 当前继续沿用第二问正式计算口径：
%
% 2月1日0:00 = 6000 kWh
%% ------------------------------------------------------------

Einitial = ...
    6000;


fprintf('储能参数：\n');

fprintf('额定容量：%.0f kWh\n', ...
    Ecapacity);

fprintf('全过程SOC范围：%.0f ~ %.0f kWh（10%%~90%%）\n', ...
    Emin,Emax);

fprintf('普通日末SOC范围：%.0f ~ %.0f kWh（10%%~90%%）\n', ...
    EdayMin,EdayMax);

fprintf('12月31日最终SOC：%.0f kWh\n', ...
    EfinalTarget);

fprintf('单个10min最大充放电量：%.2f kWh\n\n', ...
    Wmax);


%% ============================================================
% 8. LP设置
%% ============================================================

lpOptions = ...
    optimoptions( ...
    'linprog', ...
    'Algorithm','dual-simplex-highs', ...
    'Display','none');


%% ============================================================
% 9. 初始化结果
%% ============================================================

planGrid = ...
    zeros(nDay,144);


planCharge = ...
    zeros(nDay,144);


planDischarge = ...
    zeros(nDay,144);


planSOCend = ...
    zeros(nDay,1);


actualCharge = ...
    zeros(nDay,144);


actualDischarge = ...
    zeros(nDay,144);


actualCurtail = ...
    zeros(nDay,144);


emergencyGrid = ...
    zeros(nDay,144);


SOCstart = ...
    zeros(nDay,1);


SOCend = ...
    zeros(nDay,1);


planCostDay = ...
    zeros(nDay,1);


emergencyCostDay = ...
    zeros(nDay,1);


totalCostDay = ...
    zeros(nDay,1);


%% ============================================================
% 10. 全年逐日运行
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


    if mod(d-1,20)==0 || ...
       isLastDay

        fprintf( ...
            '[%03d/%03d] %s  日初SOC = %.2f kWh\n', ...
            d, ...
            nDay, ...
            string(currentDate), ...
            Ecurrent);

    end


    %% ========================================================
    % 当天真实日初SOC
    %% ========================================================

    EdayStart = ...
        Ecurrent;


    SOCstart(d) = ...
        EdayStart;


    %% ========================================================
    % 当天终端SOC约束
    %% ========================================================

    if isLastDay

        %% ----------------------------------------------------
        % 12月31日：
        %
        % 强制最终SOC回到6000 kWh
        %% ----------------------------------------------------

        terminalLow = ...
            EfinalTarget;


        terminalHigh = ...
            EfinalTarget;

    else

        %% ----------------------------------------------------
        % 普通日：
        %
        % 日末SOC可以在10%~90%之间变化
        %
        % 1200 <= Eend <= 10800
        %% ----------------------------------------------------

        terminalLow = ...
            EdayMin;


        terminalHigh = ...
            EdayMax;

    end


    %% ========================================================
    % 当天预测数据
    %% ========================================================

    loadForecast = ...
        predLoadRun(d,:)';


    pvForecast = ...
        predPVRun(d,:)';


    %% ========================================================
    % 11. 当天计划购电LP
    %
    % 普通日：
    %
    % 1200 <= E_plan,end <= 10800
    %
    % 12月31日：
    %
    % E_plan,end = 6000
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
        eta, ...
        Emin, ...
        Emax, ...
        Wmax, ...
        lpOptions);


    planGrid(d,:) = ...
        plan.Wgrid';


    planCharge(d,:) = ...
        plan.Wch';


    planDischarge(d,:) = ...
        plan.Wdis';


    planSOCend(d) = ...
        plan.E(end);


    %% ========================================================
    % 计划购电费
    %% ========================================================

    planCostDay(d) = ...
        sum( ...
        price ...
        .* plan.Wgrid);


    %% ========================================================
    % 12. 实际运行
    %
    % 固定已经制定好的Wgrid，
    % 使用当天真实负载和真实光伏。
    %
    % 同时实际运行中的SOC必须满足：
    %
    % 任意10min：
    % 1200~10800
    %
    % 普通日日末：
    % 1200~10800
    %
    % 最后一日：
    % 6000
    %% ========================================================

    loadActual = ...
        actualLoadRun(d,:)';


    pvActual = ...
        actualPVRun(d,:)';


    replay = ...
        replayActualDayTerminalSOC( ...
        loadActual, ...
        pvActual, ...
        plan.Wgrid, ...
        price, ...
        EdayStart, ...
        terminalLow, ...
        terminalHigh, ...
        dt, ...
        eta, ...
        Emin, ...
        Emax, ...
        Wmax, ...
        lpOptions);


    actualCharge(d,:) = ...
        replay.Wch';


    actualDischarge(d,:) = ...
        replay.Wdis';


    actualCurtail(d,:) = ...
        replay.Wcut';


    emergencyGrid(d,:) = ...
        replay.Wem';


    %% ========================================================
    % 实际日末SOC跨日传递
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
    % 当天总成本
    %% ========================================================

    totalCostDay(d) = ...
        planCostDay(d) ...
        + emergencyCostDay(d);


end


runtime = ...
    toc(timerMain);


%% ============================================================
% 13. 检查所有SOC约束
%% ============================================================

tolSOC = ...
    1e-5;


%% ------------------------------------------------------------
% 普通日实际日末SOC：
%
% 1200 <= SOCend <= 10800
%% ------------------------------------------------------------

normalDaySOC_OK = ...
    all( ...
    SOCend(1:end-1) ...
    >= EdayMin-tolSOC ...
    & ...
    SOCend(1:end-1) ...
    <= EdayMax+tolSOC);


%% ------------------------------------------------------------
% 最终实际SOC：
%
% 12月31日 = 6000
%% ------------------------------------------------------------

finalSOC_OK = ...
    abs( ...
    SOCend(end) ...
    - EfinalTarget) ...
    <= tolSOC;


%% ------------------------------------------------------------
% 普通日计划日末SOC：
%
% 1200 <= SOCend <= 10800
%% ------------------------------------------------------------

planNormalSOC_OK = ...
    all( ...
    planSOCend(1:end-1) ...
    >= EdayMin-tolSOC ...
    & ...
    planSOCend(1:end-1) ...
    <= EdayMax+tolSOC);


%% ------------------------------------------------------------
% 最终计划SOC：
%
% 12月31日 = 6000
%% ------------------------------------------------------------

planFinalSOC_OK = ...
    abs( ...
    planSOCend(end) ...
    - EfinalTarget) ...
    <= tolSOC;


%% ============================================================
% 14. 全年统计
%% ============================================================

totalPlanEnergy = ...
    sum( ...
    planGrid,'all');


totalEmergencyEnergy = ...
    sum( ...
    emergencyGrid,'all');


totalPlanCost = ...
    sum( ...
    planCostDay);


totalEmergencyCost = ...
    sum( ...
    emergencyCostDay);


totalCost = ...
    totalPlanCost ...
    + totalEmergencyCost;


emergencyDays = ...
    sum( ...
    any( ...
    emergencyGrid>1e-8, ...
    2));


emergencySlots = ...
    nnz( ...
    emergencyGrid>1e-8);


totalCharge = ...
    sum( ...
    actualCharge,'all');


totalDischarge = ...
    sum( ...
    actualDischarge,'all');


totalCurtail = ...
    sum( ...
    actualCurtail,'all');


fprintf('\n');

fprintf('====================================================\n');
fprintf('            问题2最终结果（SOC 10%%~90%%）\n');
fprintf('====================================================\n');


fprintf('全年计划购电量：%.2f kWh\n', ...
    totalPlanEnergy);


fprintf('全年紧急购电量：%.2f kWh\n', ...
    totalEmergencyEnergy);


fprintf('\n');


fprintf('全年计划购电费：%.2f 元\n', ...
    totalPlanCost);


fprintf('全年紧急购电费：%.2f 元\n', ...
    totalEmergencyCost);


fprintf('全年总成本：%.2f 元\n', ...
    totalCost);


fprintf('\n');


fprintf('紧急购电天数：%d 天\n', ...
    emergencyDays);


fprintf('紧急购电时段：%d 个\n', ...
    emergencySlots);


fprintf('\n');


fprintf('平均日末SOC：%.2f kWh\n', ...
    mean(SOCend));


fprintf('最小日末SOC：%.2f kWh\n', ...
    min(SOCend));


fprintf('最大日末SOC：%.2f kWh\n', ...
    max(SOCend));


fprintf('12月31日最终SOC：%.6f kWh\n', ...
    SOCend(end));


fprintf('\n');


fprintf('普通日实际SOC满足10%%~90%%：%s\n', ...
    yesno(normalDaySOC_OK));


fprintf('12月31日实际SOC=6000：%s\n', ...
    yesno(finalSOC_OK));


fprintf('普通日计划SOC满足10%%~90%%：%s\n', ...
    yesno(planNormalSOC_OK));


fprintf('12月31日计划SOC=6000：%s\n', ...
    yesno(planFinalSOC_OK));


fprintf('\n');


fprintf('全年实际充电量：%.2f kWh\n', ...
    totalCharge);


fprintf('全年实际放电量：%.2f kWh\n', ...
    totalDischarge);


fprintf('全年未利用富余电量：%.2f kWh\n', ...
    totalCurtail);


fprintf('运行时间：%.2f min\n', ...
    runtime/60);


fprintf('====================================================\n');


%% ============================================================
% 15. 如果SOC约束没满足，直接报错
%% ============================================================

if ~normalDaySOC_OK

    error( ...
        '存在普通日期实际日末SOC不在1200~10800 kWh范围内！');

end


if ~finalSOC_OK

    error( ...
        '12月31日实际最终SOC没有回到6000 kWh！');

end


if ~planNormalSOC_OK

    error( ...
        '存在普通日期计划日末SOC不在1200~10800 kWh范围内！');

end


if ~planFinalSOC_OK

    error( ...
        '12月31日计划SOC没有回到6000 kWh！');

end


%% ============================================================
% 16. SOC曲线
%% ============================================================

figure;


plot( ...
    SOCend, ...
    'LineWidth',1.3);


hold on;


yline( ...
    EdayMin, ...
    '--');


yline( ...
    EdayMax, ...
    '--');


yline( ...
    EfinalTarget, ...
    ':');


xlabel('天数');


ylabel('日末SOC / kWh');


title('问题2全年实际日末SOC（10%~90%）');


legend( ...
    '实际日末SOC', ...
    '10%容量 = 1200', ...
    '90%容量 = 10800', ...
    '年末目标 = 6000', ...
    'Location','best');


grid on;


%% ============================================================
% 17. 计划日末SOC vs 实际日末SOC
%% ============================================================

figure;


plot( ...
    planSOCend, ...
    'LineWidth',1.2);


hold on;


plot( ...
    SOCend, ...
    'LineWidth',1.2);


yline( ...
    EdayMin, ...
    '--');


yline( ...
    EdayMax, ...
    '--');


yline( ...
    EfinalTarget, ...
    ':');


xlabel('天数');


ylabel('SOC / kWh');


title('计划日末SOC与实际日末SOC（10%~90%）');


legend( ...
    '计划日末SOC', ...
    '实际日末SOC', ...
    '10% = 1200', ...
    '90% = 10800', ...
    '6000', ...
    'Location','best');


grid on;


%% ============================================================
% 18. 填写官方 result2.xlsx
%
% ★运行前请关闭Excel/WPS中的result2.xlsx
%% ============================================================

fprintf('\n正在填写官方result2.xlsx...\n');


%% ============================================================
% 18.1 计划购电量
%
% 转回官方时间顺序
%% ============================================================

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


%% 全天购电量

writematrix( ...
    sum(planGrid,2), ...
    resultFile, ...
    'Sheet','计划购电量', ...
    'Range','EP2');


%% 全天购电费

writematrix( ...
    planCostDay, ...
    resultFile, ...
    'Sheet','计划购电量', ...
    'Range','EQ2');


%% ============================================================
% 18.2 清空旧充放电结果区
%% ============================================================

blankCharge = ...
    repmat({''}, ...
    nDay*6, ...
    6);


writecell( ...
    blankCharge, ...
    resultFile, ...
    'Sheet','充放电量', ...
    'Range','A2');


%% ============================================================
% 18.3 填充充放电量
%% ============================================================

blockNames = {
    '0:00-4:00'
    '4:00-8:00'
    '8:00-12:00'
    '12:00-16:00'
    '16:00-20:00'
    '20:00-24:00'
};


nBlock = ...
    6;


chargeRows = ...
    cell( ...
    nDay*nBlock+1, ...
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


    for b = 1:nBlock


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


        %% ----------------------------------------------------
        % 第一个区间记录日初SOC
        %% ----------------------------------------------------

        if b==1


            chargeRows{row,5} = ...
                '0:00';


            chargeRows{row,6} = ...
                SOCstart(d);


        %% ----------------------------------------------------
        % 最后一个区间记录24:00 SOC
        %% ----------------------------------------------------

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


%% ============================================================
% 18.4 清空旧紧急购电结果
%% ============================================================

blankEmergency = ...
    repmat({''}, ...
    5000, ...
    3);


writecell( ...
    blankEmergency, ...
    resultFile, ...
    'Sheet','紧急购电量', ...
    'Range','A2');


%% ============================================================
% 18.5 紧急购电量
%% ============================================================

emergencyRows = {
    '日期','购电时间段','购电量'
};


for d = 1:nDay


    em = ...
        emergencyGrid(d,:);


    active = ...
        em>1e-8;


    %% --------------------------------------------------------
    % 当天无紧急购电
    %% --------------------------------------------------------

    if ~any(active)


        emergencyRows(end+1,:) = { ...
            datestr( ...
            predDates(d), ...
            'yyyy-mm-dd'), ...
            '', ...
            []};


        continue;

    end


    %% --------------------------------------------------------
    % 合并连续10min紧急购电时段
    %% --------------------------------------------------------

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


%% ============================================================
% 19. 保存MAT
%% ============================================================

save( ...
    matFile, ...
    'tauLoad', ...
    'tauPV', ...
    'planGrid', ...
    'planCharge', ...
    'planDischarge', ...
    'planSOCend', ...
    'actualCharge', ...
    'actualDischarge', ...
    'actualCurtail', ...
    'emergencyGrid', ...
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
    'totalCharge', ...
    'totalDischarge', ...
    'totalCurtail', ...
    'Ecapacity', ...
    'Emin', ...
    'Emax', ...
    'EdayMin', ...
    'EdayMax', ...
    'EfinalTarget', ...
    '-v7.3');


fprintf('\n');

fprintf('====================================================\n');

fprintf('官方result2已填写完成：\n');

fprintf('%s\n',resultFile);


fprintf('\n');


fprintf('MAT详细结果：\n');

fprintf('%s\n',matFile);


fprintf('\n');


fprintf('最终12月31日SOC = %.6f kWh\n', ...
    SOCend(end));


fprintf('====================================================\n');


%% ============================================================
% ============================================================
%                    局部函数1
%
% 每日计划LP
%
% 普通日期：
%
%   1200 <= Eend <= 10800
%
% 即：
%
%   10% <= SOC <= 90%
%
% 最后一天：
%
%   Eend = 6000
% ============================================================
%% ============================================================

function plan = solveDailyPlanTerminalSOC( ...
    Pload, ...
    Pv, ...
    price, ...
    Estart, ...
    terminalLow, ...
    terminalHigh, ...
    dt, ...
    eta, ...
    Emin, ...
    Emax, ...
    Wmax, ...
    options)


N = ...
    length(price);


Wload = ...
    Pload(:)*dt;


Wpv = ...
    Pv(:)*dt;


price = ...
    price(:);


%% ============================================================
% 决策变量
%
% Wgrid N
% Wch   N
% Wdis  N
% Wcut  N
% E     N+1
%% ============================================================

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
%
% min sum(p_t * Wgrid_t)
%
% 加极小充放电惩罚，
% 防止不必要的同时充放电
%% ============================================================

f = ...
    zeros(nvar,1);


f(idxGrid) = ...
    price;


cyclePenalty = ...
    1e-7;


f(idxCh) = ...
    cyclePenalty;


f(idxDis) = ...
    cyclePenalty;


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


%% ------------------------------------------------------------
% 电量平衡
%
% PV + grid + dis
% =
% load + ch + cut
%% ------------------------------------------------------------

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
        - Wpv(t);


end


%% ------------------------------------------------------------
% SOC动态
%
% E(t+1)
% =
% E(t)
% + eta*Wch(t)
% - Wdis(t)/eta
%% ------------------------------------------------------------

for t = 1:N


    r = ...
        N+t;


    Aeq(r,idxE(t)) = ...
        -1;


    Aeq(r,idxE(t+1)) = ...
        1;


    Aeq(r,idxCh(t)) = ...
        -eta;


    Aeq(r,idxDis(t)) = ...
        1/eta;


end


%% ------------------------------------------------------------
% 日初SOC
%% ------------------------------------------------------------

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


%% ============================================================
% 单时段最大充放电量
%% ============================================================

ub(idxCh) = ...
    Wmax;


ub(idxDis) = ...
    Wmax;


%% ============================================================
% 计划阶段未利用光伏不能超过预测光伏
%% ============================================================

ub(idxCut) = ...
    Wpv;


%% ============================================================
% ★全过程SOC约束
%
% 1200 <= E_t <= 10800
%
% 即额定容量的10%~90%
%% ============================================================

lb(idxE) = ...
    Emin;


ub(idxE) = ...
    Emax;


%% ============================================================
% ★日末SOC约束
%
% 普通日期：
%
% 1200 <= Eend <= 10800
%
% 12月31日：
%
% Eend = 6000
%% ============================================================

lb(idxE(end)) = ...
    terminalLow;


ub(idxE(end)) = ...
    terminalHigh;


%% ============================================================
% 求解
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
        ['计划LP求解失败。', ...
         '日初SOC=%.2f，日末要求=[%.2f,%.2f]'], ...
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
%                    局部函数2
%
% 实际运行LP
%
% 已知：
%
% 实际负载
% 实际光伏
% 已经确定的计划购电量 Wgrid
%
% 优化：
%
% 实际充电
% 实际放电
% 紧急购电
% 未利用富余电量
%
% SOC全过程限制：
%
% 1200 <= E_t <= 10800
%
% 普通日日末：
%
% 1200 <= Eend <= 10800
%
% 最后一天：
%
% Eend = 6000
% ============================================================
%% ============================================================

function replay = replayActualDayTerminalSOC( ...
    Pload, ...
    Pv, ...
    Wgrid, ...
    price, ...
    Estart, ...
    terminalLow, ...
    terminalHigh, ...
    dt, ...
    eta, ...
    Emin, ...
    Emax, ...
    Wmax, ...
    options)


N = ...
    length(Wgrid);


Wload = ...
    Pload(:)*dt;


Wpv = ...
    Pv(:)*dt;


Wgrid = ...
    Wgrid(:);


price = ...
    price(:);


%% ============================================================
% 决策变量
%
% Wch    N
% Wdis   N
% Wcut   N
% Wem    N
% E      N+1
%% ============================================================

idxCh = ...
    1:N;


idxDis = ...
    N+(1:N);


idxCut = ...
    2*N+(1:N);


idxEm = ...
    3*N+(1:N);


idxE = ...
    4*N+(1:N+1);


nvar = ...
    5*N+1;


%% ============================================================
% 目标函数
%
% 紧急购电按5倍电价
%
% 加极小充放电惩罚，
% 防止无意义同时充放电
%% ============================================================

f = ...
    zeros(nvar,1);


f(idxEm) = ...
    5*price;


cyclePenalty = ...
    1e-7;


f(idxCh) = ...
    cyclePenalty;


f(idxDis) = ...
    cyclePenalty;


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


%% ------------------------------------------------------------
% 实际供需平衡
%
% actualPV
% + plannedGrid
% + discharge
% + emergency
%
% =
%
% actualLoad
% + charge
% + unusedSurplus
%% ------------------------------------------------------------

for t = 1:N


    Aeq(t,idxCh(t)) = ...
        -1;


    Aeq(t,idxDis(t)) = ...
        1;


    Aeq(t,idxCut(t)) = ...
        -1;


    Aeq(t,idxEm(t)) = ...
        1;


    beq(t) = ...
        Wload(t) ...
        - Wpv(t) ...
        - Wgrid(t);


end


%% ------------------------------------------------------------
% SOC动态
%
% E(t+1)
% =
% E(t)
% + eta*Wch(t)
% - Wdis(t)/eta
%% ------------------------------------------------------------

for t = 1:N


    r = ...
        N+t;


    Aeq(r,idxE(t)) = ...
        -1;


    Aeq(r,idxE(t+1)) = ...
        1;


    Aeq(r,idxCh(t)) = ...
        -eta;


    Aeq(r,idxDis(t)) = ...
        1/eta;


end


%% ============================================================
% 日初SOC
%% ============================================================

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


%% ============================================================
% 最大充放电量限制
%% ============================================================

ub(idxCh) = ...
    Wmax;


ub(idxDis) = ...
    Wmax;


%% ============================================================
% ★全过程SOC物理范围
%
% 1200 <= E_t <= 10800
%
% 即10%~90%
%% ============================================================

lb(idxE) = ...
    Emin;


ub(idxE) = ...
    Emax;


%% ============================================================
% ★实际日末SOC限制
%
% 普通日：
%
% 1200 <= Eend <= 10800
%
% 最后一天：
%
% Eend = 6000
%% ============================================================

lb(idxE(end)) = ...
    terminalLow;


ub(idxE(end)) = ...
    terminalHigh;


%% ============================================================
% 求解
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
        ['实际运行LP不可行。', ...
         '日初SOC=%.2f，日末要求=[%.2f,%.2f]'], ...
        Estart, ...
        terminalLow, ...
        terminalHigh);

end


replay.Wch = ...
    x(idxCh);


replay.Wdis = ...
    x(idxDis);


replay.Wcut = ...
    x(idxCut);


replay.Wem = ...
    x(idxEm);


replay.E = ...
    x(idxE);


replay.Eend = ...
    x(idxE(end));


end


%% ============================================================
%                    局部函数3
%
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
%                    局部函数4
%
% 是/否输出
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