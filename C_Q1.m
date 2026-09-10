%% 2026 数模 C题 问题1
% 微网全天计划购电策略
% 模型：线性规划 + 显式弃光量 Wcut

clear;
clc;
close all;

%% 1. 读取附件1
filename = '附件1.xlsx';

T = readtable(filename, 'VariableNamingRule','preserve');

% 默认附件1：
% 第1列 时间
% 第2列 电价 price（元/kWh）
% 第3列 小区负载功率（kW）
% 第4列 光伏预测功率（kW）

time_raw = T{:,1};
price    = T{:,2};
Pload    = T{:,3};
Pv       = T{:,4};

price = price(:);
Pload = Pload(:);
Pv    = Pv(:);

N = length(price);

fprintf('共有 %d 个时间段\n',N);

%% 2. 功率转电量

% 每个时间段10 min
dt = 10/60;     % h

Wload = Pload * dt;      % kWh
Wv    = Pv * dt;         % kWh

%% 3. 储能参数

eta = 0.90;

E0   = 6000;     % kWh
Emin = 1200;
Emax = 10800;

Pmax = 5000;     % kW

% 每10分钟最大充放电量
Wmax = Pmax * dt;

fprintf('每10分钟最大充放电量 = %.4f kWh\n',Wmax);

%% 4. 决策变量

% x =
%
% [Wgrid]
% [Wch]
% [Wdis]
% [Wcut]
% [E]
%
% Wgrid : N
% Wch   : N
% Wdis  : N
% Wcut  : N
% E     : N+1

idx_grid = 1:N;
idx_ch   = N + (1:N);
idx_dis  = 2*N + (1:N);
idx_cut  = 3*N + (1:N);
idx_E    = 4*N + (1:N+1);

nvar = 5*N + 1;

%% 5. 目标函数

% min sum(price .* Wgrid)

f = zeros(nvar,1);

f(idx_grid) = price;

%% 6. 等式约束

% 一共有：
%
% N个电量平衡方程
% N个储能动态方程
% 1个初始电量约束
% 1个最终电量约束

Aeq = zeros(2*N+2,nvar);
beq = zeros(2*N+2,1);


%% 6.1 电量平衡

% Wv + Wgrid + Wdis
% =
% Wload + Wch + Wcut
%
% 整理：
%
% Wgrid - Wch + Wdis - Wcut
% =
% Wload - Wv

for t = 1:N

    Aeq(t,idx_grid(t)) = 1;
    Aeq(t,idx_ch(t))   = -1;
    Aeq(t,idx_dis(t))  = 1;
    Aeq(t,idx_cut(t))  = -1;

    beq(t) = Wload(t) - Wv(t);

end

%% 6.2 储能动态方程

% E(t+1)
% =
% E(t) + eta*Wch - Wdis/eta
%
% 整理：
%
% E(t+1)-E(t)-eta*Wch+Wdis/eta = 0

for t = 1:N

    row = N + t;

    Aeq(row,idx_E(t))     = -1;
    Aeq(row,idx_E(t+1))   = 1;

    Aeq(row,idx_ch(t))    = -eta;
    Aeq(row,idx_dis(t))   = 1/eta;

    beq(row) = 0;

end

%% 6.3 初始储电量

Aeq(2*N+1,idx_E(1)) = 1;
beq(2*N+1) = E0;

%% 6.4 24:00储电量

Aeq(2*N+2,idx_E(end)) = 1;
beq(2*N+2) = E0;

%% 7. 不等式约束

% 本模型暂时没有额外的不等式约束
A = [];
b = [];

%% 8. 变量上下界

lb = zeros(nvar,1);
ub = inf(nvar,1);

% 外网购电
lb(idx_grid) = 0;

% 充电
lb(idx_ch) = 0;
ub(idx_ch) = Wmax;

% 放电
lb(idx_dis) = 0;
ub(idx_dis) = Wmax;

% 弃光
lb(idx_cut) = 0;

% 储能电量
lb(idx_E) = Emin;
ub(idx_E) = Emax;

%% 9. 求解线性规划

options = optimoptions( ...
    'linprog', ...
    'Display','iter');

[x,fval,exitflag,output] = linprog( ...
    f,A,b,Aeq,beq,lb,ub,options);

if exitflag <= 0
    error('优化失败，请检查数据和模型');
end

fprintf('\n===============================\n');
fprintf('问题1优化成功\n');
fprintf('===============================\n');

%% 10. 提取结果

Wgrid = x(idx_grid);
Wch   = x(idx_ch);
Wdis  = x(idx_dis);
Wcut  = x(idx_cut);
E     = x(idx_E);

%% 11. 全天结果

total_grid = sum(Wgrid);
total_cost = sum(price .* Wgrid);
total_cut  = sum(Wcut);

fprintf('全天购电量 = %.4f kWh\n',total_grid);
fprintf('全天购电费 = %.4f 元\n',total_cost);
fprintf('全天弃光量 = %.4f kWh\n',total_cut);

fprintf('0:00储电量  = %.4f kWh\n',E(1));
fprintf('24:00储电量 = %.4f kWh\n',E(end));

fprintf('最低储电量  = %.4f kWh\n',min(E));
fprintf('最高储电量  = %.4f kWh\n',max(E));

%% 12. 检验电量平衡

balance_error = ...
    Wv + Wgrid + Wdis ...
    - Wload - Wch - Wcut;

fprintf('最大电量平衡误差 = %.10f kWh\n', ...
    max(abs(balance_error)));

%% 13. 表1指定时间购电量

hours_select = [10 12 14 16 18 20];

idx_select = hours_select*6 ;

fprintf('\n====== 表1指定时段购电量 ======\n');

for i = 1:length(hours_select)

    t = idx_select(i);

    fprintf('%02d:00-%02d:10：%.4f kWh\n', ...
        hours_select(i), ...
        hours_select(i), ...
        Wgrid(t));

end

fprintf('\n全天购电量：%.4f kWh\n',total_grid);
fprintf('全天购电费：%.4f 元\n',total_cost);

%% 14. 表2：每4小时充放电量

charge4h    = zeros(6,1);
discharge4h = zeros(6,1);

fprintf('\n====== 表2储能充放电量 ======\n');

for k = 1:6

    i1 = (k-1)*24 + 1;
    i2 = k*24;

    charge4h(k) = sum(Wch(i1:i2));
    discharge4h(k) = sum(Wdis(i1:i2));

    fprintf('%02d:00-%02d:00：充电 %.4f，放电 %.4f kWh\n', ...
        (k-1)*4,k*4, ...
        charge4h(k), ...
        discharge4h(k));

end

fprintf('0:00储电量  = %.4f kWh\n',E(1));
fprintf('24:00储电量 = %.4f kWh\n',E(end));

%% 15. 画图

time_h = (0:N-1)*dt;

% 外网购电
figure;
plot(time_h,Wgrid,'LineWidth',1.5);
xlabel('时间 / h');
ylabel('购电量 / kWh');
title('全天计划购电量');
grid on;

% 充放电
figure;
plot(time_h,Wch,'LineWidth',1.5);
hold on;
plot(time_h,Wdis,'LineWidth',1.5);

xlabel('时间 / h');
ylabel('电量 / kWh');
legend('充电量 Wch','放电量 Wdis');
title('储能充放电策略');
grid on;

% 储能SOC
figure;

time_E = (0:N)*dt;

plot(time_E,E,'LineWidth',1.5);

xlabel('时间 / h');
ylabel('储电量 / kWh');
title('储能设备电量变化');
grid on;

% 弃光
figure;

plot(time_h,Wcut,'LineWidth',1.5);

xlabel('时间 / h');
ylabel('弃光量 / kWh');
title('光伏弃光量');
grid on;

%% ==================== 16.输出官方 result1.xlsx ====================

outputFile = ...
    'E:\数模\2026年正式比赛\CUMCM2026Problems\C题\附件\附件5\result1.xlsx';

%% ---------- 1. 写入144个10分钟购电量 ----------

% 官方模板：
% 计划购电量工作表
% A列已有时间段
% B2:B145 填写购电量

if length(Wgrid) ~= 144
    error('Wgrid数量不是144，请检查前面的数据读取和模型！');
end

writematrix(Wgrid, ...
    outputFile, ...
    'Sheet','计划购电量', ...
    'Range','B2');


%% ---------- 2. 计算6个4小时区间充放电量 ----------

charge4h = zeros(6,1);
discharge4h = zeros(6,1);

for k = 1:6

    % 每4小时 = 24个10分钟时段
    i1 = (k-1)*24 + 1;
    i2 = k*24;

    charge4h(k) = sum(Wch(i1:i2));
    discharge4h(k) = sum(Wdis(i1:i2));

end


%% ---------- 3. 写入充放电量 ----------

% B2:B7：充电量
writematrix(charge4h, ...
    outputFile, ...
    'Sheet','充放电量', ...
    'Range','B2');

% C2:C7：放电量
writematrix(discharge4h, ...
    outputFile, ...
    'Sheet','充放电量', ...
    'Range','C2');


%% ---------- 4. 写入0:00和24:00储电量 ----------

% E2：0:00储电量
writematrix(E(1), ...
    outputFile, ...
    'Sheet','充放电量', ...
    'Range','E2');

% E3：24:00储电量
writematrix(E(end), ...
    outputFile, ...
    'Sheet','充放电量', ...
    'Range','E3');


%% ---------- 5. 输出检查 ----------

fprintf('\n====================================\n');
fprintf('result1.xlsx 已写入完成！\n');
fprintf('文件位置：\n%s\n',outputFile);
fprintf('====================================\n');

fprintf('写入购电量数量：%d\n',length(Wgrid));
fprintf('0:00储电量：%.4f kWh\n',E(1));
fprintf('24:00储电量：%.4f kWh\n',E(end));

fprintf('\n六个时段充放电量：\n');

for k = 1:6
    fprintf('第%d段：充电 %.4f kWh，放电 %.4f kWh\n', ...
        k,charge4h(k),discharge4h(k));
end