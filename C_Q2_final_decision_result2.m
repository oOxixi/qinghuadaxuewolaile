%% ============================================================
% 2026 C题 问题2 最终决策
%
% 预测模型：
% 负载：QAR tau_L = 0.80
% 光伏：AS-Ridge 非对称参数 = 0.20
%
% 功能：
% 1. 读取已经得到的负载/光伏预测结果
% 2. 每日0:00建立购电-储能线性规划
% 3. 用实际负载/光伏进行真实运行回放
% 4. 计算紧急购电
% 5. 统计全年成本
% 6. 自动写入附件5 result2.xlsx
%
%% ============================================================

clear;
clc;
close all;


fprintf('====================================================\n');
fprintf(' C题问题2 最终决策\n');
fprintf(' 负载：QAR tau=0.8\n');
fprintf(' 光伏：AS-Ridge 非对称参数=0.2\n');
fprintf('====================================================\n\n');


%% ============================================================
% 1. 路径
%% ============================================================

baseDir = ...
    'E:\数模\2026年正式比赛\CUMCM2026Problems\C题\附件';


%% 预测结果

predictionFile = ...
    fullfile( ...
    baseDir, ...
    'Q2_QAR_ASRidge_predictions.mat');


%% 附件1：电价

priceFile = ...
    fullfile( ...
    baseDir, ...
    '附件1.xlsx');


%% result2模板
%
% 如果你的result2.xlsx就在附件5文件夹中，
% 保持下面写法
%% ============================================================

resultFile = ...
    fullfile( ...
    baseDir, ...
    '附件5', ...
    'result2.xlsx');


%% 如果实际result2.xlsx直接放在“附件”文件夹，
% 把上一段改成：
%
% resultFile = fullfile(baseDir,'result2.xlsx');


if ~isfile(predictionFile)

    error('找不到预测结果文件：%s',predictionFile);

end


if ~isfile(priceFile)

    error('找不到附件1.xlsx：%s',priceFile);

end


if ~isfile(resultFile)

    error('找不到result2.xlsx：%s',resultFile);

end


fprintf('预测结果：%s\n',predictionFile);

fprintf('结果模板：%s\n\n',resultFile);


%% ============================================================
% 2. 先备份result2
%% ============================================================

backupFile = ...
    fullfile( ...
    fileparts(resultFile), ...
    'result2_backup.xlsx');


copyfile( ...
    resultFile, ...
    backupFile);


fprintf('已备份原模板：\n%s\n\n',backupFile);


%% ============================================================
% 3. 读取预测结果
%% ============================================================

S = ...
    load(predictionFile);


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
        (datetime(2025,2,1):days(1):datetime(2025,12,31))';

end


[nPredDay,nTime] = ...
    size(predLoad);


if nPredDay~=334 || nTime~=144

    error( ...
        '预测结果尺寸应为334×144，当前为%d×%d', ...
        nPredDay,nTime);

end


fprintf('预测数据读取完成：%d天 × %d时段\n\n', ...
    nPredDay,nTime);


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

    error('附件1中的电价不是144个时段');

end


%% ============================================================
% 5. 时间轴转换
%
% 原始附件顺序：
%
% 00:10
% 00:20
% ...
% 23:50
% 00:00(+1)
%
% 内部优化统一转换成：
%
% 00:00-00:10
% 00:10-00:20
% ...
% 23:50-24:00
%
%% ============================================================

idx = ...
    [144,1:143];


%% 电价

price = ...
    [ ...
    priceRaw(end);
    priceRaw(1:end-1)];


%% 实际数据

actualLoadRun = ...
    actualLoad(:,idx);


actualPVRun = ...
    actualPV(:,idx);


%% 预测数据

predLoadRun = ...
    predLoad(:,idx);


predPVRun = ...
    predPV(:,idx);


%% ============================================================
% 6. 储能参数
%% ============================================================

dt = ...
    10/60;


eta = ...
    0.90;


Emin = ...
    1200;


Emax = ...
    10800;


Pmax = ...
    5000;


%% 单个10min最大充放电量

Wmax = ...
    Pmax*dt;


%% ------------------------------------------------------------
% 当前问题2计算中：
% 2月1日开始时SOC设置为6000 kWh
%% ------------------------------------------------------------

Einitial = ...
    6000;


%% 紧急购电价格倍数

emergencyFactor = ...
    5;


fprintf('储能参数：\n');

fprintf('Emin = %.0f kWh\n',Emin);

fprintf('Emax = %.0f kWh\n',Emax);

fprintf('初始SOC = %.0f kWh\n',Einitial);

fprintf('单时段最大充放电量 = %.3f kWh\n\n',Wmax);


%% ============================================================
% 7. linprog设置
%% ============================================================

lpOptions = ...
    optimoptions( ...
    'linprog', ...
    'Algorithm','dual-simplex-highs', ...
    'Display','none');


%% ============================================================
% 8. 保存每日最终结果
%% ============================================================

%% 计划购电量
% 内部时间：
% 00:00-0:10 ... 23:50-24:00

planGrid = ...
    zeros(nPredDay,nTime);


%% 实际运行充电量

actualCharge = ...
    zeros(nPredDay,nTime);


%% 实际运行放电量

actualDischarge = ...
    zeros(nPredDay,nTime);


%% 实际弃光

actualCurtail = ...
    zeros(nPredDay,nTime);


%% 紧急购电

emergencyGrid = ...
    zeros(nPredDay,nTime);


%% 每日SOC

SOCstart = ...
    zeros(nPredDay,1);


SOCend = ...
    zeros(nPredDay,1);


%% 每日费用

planCostDay = ...
    zeros(nPredDay,1);


emergencyCostDay = ...
    zeros(nPredDay,1);


%% ============================================================
% 9. 全年逐日优化
%% ============================================================

Ecurrent = ...
    Einitial;


tic;


for d = 1:nPredDay


    if mod(d-1,20)==0 || d==nPredDay

        fprintf( ...
            '[%03d/%03d] %s\n', ...
            d,nPredDay,string(predDates(d)));

    end


    %% --------------------------------------------------------
    % 当天QAR负载预测
    %% --------------------------------------------------------

    loadForecast = ...
        predLoadRun(d,:)';


    %% --------------------------------------------------------
    % 当天AS-Ridge光伏预测
    %% --------------------------------------------------------

    pvForecast = ...
        predPVRun(d,:)';


    %% --------------------------------------------------------
    % 当天真实数据
    %% --------------------------------------------------------

    loadActual = ...
        actualLoadRun(d,:)';


    pvActual = ...
        actualPVRun(d,:)';


    %% ========================================================
    % 当天开始SOC
    %% ========================================================

    SOCstart(d) = ...
        Ecurrent;


    %% ========================================================
    % 0:00 根据预测结果制定全天计划
    %% ========================================================

    plan = ...
        solveDailyPlanLP( ...
        loadForecast, ...
        pvForecast, ...
        price, ...
        Ecurrent, ...
        dt, ...
        eta, ...
        Emin, ...
        Emax, ...
        Wmax, ...
        lpOptions);


    planGrid(d,:) = ...
        plan.Wgrid';


    %% --------------------------------------------------------
    % 当天计划购电费
    %% --------------------------------------------------------

    planCostDay(d) = ...
        sum( ...
        price ...
        .* plan.Wgrid);


    %% ========================================================
    % 用实际负载+实际光伏回放
    %% ========================================================

    replay = ...
        replayActualDay( ...
        loadActual, ...
        pvActual, ...
        plan.Wgrid, ...
        Ecurrent, ...
        dt, ...
        eta, ...
        Emin, ...
        Emax, ...
        Wmax);


    actualCharge(d,:) = ...
        replay.Wch';


    actualDischarge(d,:) = ...
        replay.Wdis';


    actualCurtail(d,:) = ...
        replay.Wcut';


    emergencyGrid(d,:) = ...
        replay.Wem';


    %% --------------------------------------------------------
    % 紧急购电费用
    %% --------------------------------------------------------

    emergencyCostDay(d) = ...
        sum( ...
        emergencyFactor ...
        .* price ...
        .* replay.Wem);


    %% --------------------------------------------------------
    % SOC传递到下一天
    %% --------------------------------------------------------

    Ecurrent = ...
        replay.Eend;


    SOCend(d) = ...
        Ecurrent;


end


runtime = ...
    toc;


fprintf('\n全年优化完成，耗时 %.2f min\n\n', ...
    runtime/60);


%% ============================================================
% 10. 全年统计
%% ============================================================

totalPlanEnergy = ...
    sum(planGrid,'all');


totalEmergencyEnergy = ...
    sum(emergencyGrid,'all');


totalPlanCost = ...
    sum(planCostDay);


totalEmergencyCost = ...
    sum(emergencyCostDay);


totalCost = ...
    totalPlanCost ...
    + totalEmergencyCost;


emergencyDays = ...
    sum( ...
    any(emergencyGrid>1e-8,2));


emergencySlots = ...
    nnz(emergencyGrid>1e-8);


fprintf('====================================================\n');

fprintf('最终结果\n');

fprintf('====================================================\n');

fprintf('全年计划购电量：%.2f kWh\n', ...
    totalPlanEnergy);

fprintf('全年紧急购电量：%.2f kWh\n', ...
    totalEmergencyEnergy);

fprintf('全年计划购电费：%.2f 元\n', ...
    totalPlanCost);

fprintf('全年紧急购电费：%.2f 元\n', ...
    totalEmergencyCost);

fprintf('全年总成本：%.2f 元\n', ...
    totalCost);

fprintf('发生紧急购电天数：%d 天\n', ...
    emergencyDays);

fprintf('发生紧急购电时段：%d 个\n', ...
    emergencySlots);

fprintf('年末SOC：%.2f kWh\n', ...
    SOCend(end));

fprintf('====================================================\n\n');


%% ============================================================
% 11. 写入“计划购电量”
%
% result2模板顺序：
%
% 0:10-0:20
% ...
% 23:50-0:00+1
% 0:00-0:10+1
%
% 所以需要把内部时间重新转回模板顺序
%% ============================================================

planGridOut = ...
    [ ...
    planGrid(:,2:end), ...
    planGrid(:,1)];


%% ------------------------------------------------------------
% 全天购电量
%% ------------------------------------------------------------

dailyPlanEnergy = ...
    sum(planGrid,2);


%% ------------------------------------------------------------
% 写144个购电时段
%
% B:EO
%% ------------------------------------------------------------

writematrix( ...
    planGridOut, ...
    resultFile, ...
    'Sheet','计划购电量', ...
    'Range','B2');


%% ------------------------------------------------------------
% 全天购电量
%
% EP列
%% ------------------------------------------------------------

writematrix( ...
    dailyPlanEnergy, ...
    resultFile, ...
    'Sheet','计划购电量', ...
    'Range','EP2');


%% ------------------------------------------------------------
% 全天购电费
%
% EQ列
%% ------------------------------------------------------------

writematrix( ...
    planCostDay, ...
    resultFile, ...
    'Sheet','计划购电量', ...
    'Range','EQ2');


fprintf('“计划购电量”工作表填写完成。\n');


%% ============================================================
% 12. 写入“充放电量”
%
% 每天：
%
% 0:00-4:00
% 4:00-8:00
% 8:00-12:00
% 12:00-16:00
% 16:00-20:00
% 20:00-24:00
%
% 每4小时 = 24个10min时段
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


nChargeRows = ...
    nPredDay*nBlock;


chargeCell = ...
    cell(nChargeRows+1,6);


%% 表头

chargeCell(1,:) = {
    '日期'
    '时间段'
    '充电量'
    '放电量'
    '时刻'
    '储电量'
};


row = ...
    2;


for d = 1:nPredDay


    for b = 1:nBlock


        %% 24个10min时段构成4小时

        slots = ...
            (b-1)*24+1 : b*24;


        %% ----------------------------------------------------
        % 日期只在每天第一行填写
        %% ----------------------------------------------------

        if b==1

            chargeCell{row,1} = ...
                datestr(predDates(d),'yyyy-mm-dd');

        else

            chargeCell{row,1} = ...
                '';

        end


        %% 时间段

        chargeCell{row,2} = ...
            blockNames{b};


        %% 4小时累计充电量

        chargeCell{row,3} = ...
            sum(actualCharge(d,slots));


        %% 4小时累计放电量

        chargeCell{row,4} = ...
            sum(actualDischarge(d,slots));


        %% ----------------------------------------------------
        % 模板中只要求：
        % 0:00 SOC
        % 24:00 SOC
        %% ----------------------------------------------------

        if b==1

            chargeCell{row,5} = ...
                '0:00';

            chargeCell{row,6} = ...
                SOCstart(d);

        elseif b==2

            chargeCell{row,5} = ...
                '24:00';

            chargeCell{row,6} = ...
                SOCend(d);

        else

            chargeCell{row,5} = ...
                '';

            chargeCell{row,6} = ...
                [];

        end


        row = ...
            row+1;


    end


end


%% ------------------------------------------------------------
% 整体覆盖“充放电量”工作表
%% ------------------------------------------------------------

writecell( ...
    chargeCell, ...
    resultFile, ...
    'Sheet','充放电量', ...
    'Range','A1');


fprintf('“充放电量”工作表填写完成。\n');


%% ============================================================
% 13. 写入“紧急购电量”
%
% 这里不是机械地把每个10min都写一行，
% 而是把连续发生紧急购电的10min时段合并，
% 更符合模板“购电时间段”的含义。
%% ============================================================

%% ------------------------------------------------------------
% 读取模板中的官方时间段名称
%
% B1:EO1正好是144个时段
%% ------------------------------------------------------------

templateHeaders = ...
    readcell( ...
    resultFile, ...
    'Sheet','计划购电量', ...
    'Range','B1:EO1');


timeLabels = ...
    templateHeaders(:);


%% 紧急购电同样转成模板时间顺序

emergencyOut = ...
    [ ...
    emergencyGrid(:,2:end), ...
    emergencyGrid(:,1)];


%% ------------------------------------------------------------
% 最多预分配
%% ------------------------------------------------------------

emergencyRows = {
    '日期','购电时间段','购电量'
};


for d = 1:nPredDay


    em = ...
        emergencyOut(d,:);


    active = ...
        em>1e-8;


    %% ========================================================
    % 当天完全没有紧急购电
    %
    % 仍保留日期，
    % 便于结果表覆盖完整日期
    %% ========================================================

    if ~any(active)


        emergencyRows(end+1,:) = { ...
            datestr(predDates(d),'yyyy-mm-dd'), ...
            '', ...
            []};


        continue;


    end


    %% ========================================================
    % 找连续紧急购电区段
    %% ========================================================

    diffActive = ...
        diff([false active false]);


    startIdx = ...
        find(diffActive==1);


    endIdx = ...
        find(diffActive==-1)-1;


    nEvent = ...
        length(startIdx);


    for e = 1:nEvent


        s = ...
            startIdx(e);


        f = ...
            endIdx(e);


        %% ----------------------------------------------------
        % 合并的总紧急购电量
        %% ----------------------------------------------------

        eventEnergy = ...
            sum(em(s:f));


        %% ----------------------------------------------------
        % 时间段
        %
        % 若只有一个10min：
        % 直接用模板标签
        %
        % 若连续多个：
        % 合并成起止区间
        %% ----------------------------------------------------

        if s==f


            eventLabel = ...
                timeLabels{s};


        else


            startLabel = ...
                timeLabels{s};


            endLabel = ...
                timeLabels{f};


            %% 拆取：
            % 例如
            % 8:00-8:10
            % 8:10-8:20
            %
            % 合并：
            % 8:00-8:20

            p1 = ...
                split(string(startLabel),'-');


            p2 = ...
                split(string(endLabel),'-');


            eventLabel = ...
                char( ...
                p1(1) ...
                + "-" ...
                + p2(end));


        end


        %% ----------------------------------------------------
        % 日期只在当天第一条紧急购电记录填写
        %% ----------------------------------------------------

        if e==1

            dateValue = ...
                datestr(predDates(d),'yyyy-mm-dd');

        else

            dateValue = ...
                '';

        end


        emergencyRows(end+1,:) = { ...
            dateValue, ...
            eventLabel, ...
            eventEnergy};


    end


end


%% ============================================================
% 14. 清理原“紧急购电量”工作表旧内容
%% ============================================================

%% 先用足够大的空白区域覆盖旧模板示例

clearRows = ...
    max(size(emergencyRows,1)+20,5000);


emptyCell = ...
    cell(clearRows,3);


writecell( ...
    emptyCell, ...
    resultFile, ...
    'Sheet','紧急购电量', ...
    'Range','A1');


%% 再写正式结果

writecell( ...
    emergencyRows, ...
    resultFile, ...
    'Sheet','紧急购电量', ...
    'Range','A1');


fprintf('“紧急购电量”工作表填写完成。\n');


%% ============================================================
% 15. 保存完整决策结果MAT
%% ============================================================

save( ...
    fullfile( ...
    baseDir, ...
    'Q2_final_decision.mat'), ...
    'planGrid', ...
    'actualCharge', ...
    'actualDischarge', ...
    'actualCurtail', ...
    'emergencyGrid', ...
    'SOCstart', ...
    'SOCend', ...
    'planCostDay', ...
    'emergencyCostDay', ...
    'totalPlanEnergy', ...
    'totalEmergencyEnergy', ...
    'totalPlanCost', ...
    'totalEmergencyCost', ...
    'totalCost', ...
    '-v7.3');


%% ============================================================
% 16. 完成
%% ============================================================

fprintf('\n');

fprintf('====================================================\n');

fprintf('result2.xlsx 已填写完成！\n');

fprintf('\n文件位置：\n');

fprintf('%s\n',resultFile);

fprintf('\n原模板备份：\n');

fprintf('%s\n',backupFile);

fprintf('====================================================\n');


%% ============================================================
% 局部函数1：
% 每日计划购电线性规划
%% ============================================================

function plan = solveDailyPlanLP( ...
    Pload,Pv,price,Estart, ...
    dt,eta,Emin,Emax,Wmax,options)


N = ...
    length(price);


%% 功率 -> 10min电量

Wload = ...
    Pload(:)*dt;


Wv = ...
    Pv(:)*dt;


price = ...
    price(:);


%% ============================================================
% 决策变量
%
% x =
%
% Wgrid(1:N)
% Wch(1:N)
% Wdis(1:N)
% Wcut(1:N)
% E(1:N+1)
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
% 目标：
%
% min sum price*Wgrid
%% ============================================================

f = ...
    zeros(nvar,1);


f(idxGrid) = ...
    price;


%% ============================================================
% 等式约束
%% ============================================================

Aeq = ...
    zeros(2*N+2,nvar);


beq = ...
    zeros(2*N+2,1);


%% ------------------------------------------------------------
% 能量平衡
%
% Pv + Grid + Dis
% =
% Load + Ch + Cut
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
        Wload(t)-Wv(t);


end


%% ------------------------------------------------------------
% SOC动态
%
% E(t+1)
% =
% E(t)
% + eta*Wch
% - Wdis/eta
%% ------------------------------------------------------------

for t = 1:N


    row = ...
        N+t;


    Aeq(row,idxE(t)) = ...
        -1;


    Aeq(row,idxE(t+1)) = ...
        1;


    Aeq(row,idxCh(t)) = ...
        -eta;


    Aeq(row,idxDis(t)) = ...
        1/eta;


end


%% ============================================================
% 初始SOC
%% ============================================================

Aeq(2*N+1,idxE(1)) = ...
    1;


beq(2*N+1) = ...
    Estart;


%% ============================================================
% 日终SOC = 日初SOC
%
% 防止24h优化在末尾人为放空储能
%% ============================================================

Aeq(2*N+2,idxE(end)) = ...
    1;


beq(2*N+2) = ...
    Estart;


%% ============================================================
% 上下界
%% ============================================================

lb = ...
    zeros(nvar,1);


ub = ...
    inf(nvar,1);


%% 最大充放电

ub(idxCh) = ...
    Wmax;


ub(idxDis) = ...
    Wmax;


%% 弃光不能超过光伏发电量

ub(idxCut) = ...
    Wv;


%% SOC

lb(idxE) = ...
    Emin;


ub(idxE) = ...
    Emax;


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

    error('每日计划LP求解失败');

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
% 局部函数2：
% 实际运行回放
%% ============================================================

function replay = replayActualDay( ...
    Pload,Pv,Wgrid,Estart, ...
    dt,eta,Emin,Emax,Wmax)


N = ...
    length(Wgrid);


Wload = ...
    Pload(:)*dt;


Wv = ...
    Pv(:)*dt;


Wgrid = ...
    Wgrid(:);


Wch = ...
    zeros(N,1);


Wdis = ...
    zeros(N,1);


Wem = ...
    zeros(N,1);


Wcut = ...
    zeros(N,1);


E = ...
    zeros(N+1,1);


E(1) = ...
    Estart;


for t = 1:N


    %% ========================================================
    % 当前时段供需差
    %% ========================================================

    balance = ...
        Wv(t) ...
        + Wgrid(t) ...
        - Wload(t);


    %% ========================================================
    % 供电富余
    %% ========================================================

    if balance>=0


        %% 还能充多少电

        capacityLimit = ...
            max( ...
            (Emax-E(t))/eta, ...
            0);


        Wch(t) = ...
            min([ ...
            balance, ...
            Wmax, ...
            capacityLimit]);


        E(t+1) = ...
            E(t) ...
            + eta*Wch(t);


        %% 多余光伏

        Wcut(t) = ...
            balance ...
            - Wch(t);


    %% ========================================================
    % 供电不足
    %% ========================================================

    else


        deficit = ...
            -balance;


        %% SOC允许的最大放电量

        socLimit = ...
            max( ...
            (E(t)-Emin)*eta, ...
            0);


        Wdis(t) = ...
            min([ ...
            deficit, ...
            Wmax, ...
            socLimit]);


        E(t+1) = ...
            E(t) ...
            - Wdis(t)/eta;


        %% 储能仍覆盖不了的缺口

        Wem(t) = ...
            deficit ...
            - Wdis(t);


    end


    %% 数值修正

    if E(t+1)<Emin && ...
       E(t+1)>Emin-1e-8

        E(t+1) = ...
            Emin;

    end


    if E(t+1)>Emax && ...
       E(t+1)<Emax+1e-8

        E(t+1) = ...
            Emax;

    end


end


replay.Wch = ...
    Wch;


replay.Wdis = ...
    Wdis;


replay.Wem = ...
    Wem;


replay.Wcut = ...
    Wcut;


replay.E = ...
    E;


replay.Eend = ...
    E(end);


end