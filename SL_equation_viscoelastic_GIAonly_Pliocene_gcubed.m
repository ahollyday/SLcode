

%  Copyright (C) 2016 - 2017 by J. Austermann.
%  This file is part of SLcode.
%  SLcode is free software; you can redistribute it and/or modify
%  it under the terms of the GNU General Public License as published by
%  the Free Software Foundation; either version 2, or (at your option)
%  any later version.
%  SLcode is distributed in the hope that it will be useful,
%  but WITHOUT ANY WARRANTY; without even the implied warranty of
%  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%  GNU General Public License for more details.
%  <http://www.gnu.org/licenses/>.


% Code to solve the elastic sea level equation following 
% Kendall et al., 2005 and Austermann et al., 2015

% J. Austermann 2016

% add paths when run for the first time.
% addpath SLFunctions
% addpath '/Users/jackyaustermann/Documents/MATLAB/m_map'

%% Parameters & Input 
% Specify maximum degree to which spherical transformations should be done
maxdeg = 256;%64;%256;

% Some options to choose from
include_rotation = 'y'; % choose between y (for yes) and n (for no)
include_ice_check = 'y'; % choose between y (for yes) and n (for no)

% parameters
rho_ice = 920;
rho_water = 1000;
g = 9.80665;


% The following steps help speed up the calculations
% Set up Gauss Legendre grid onto which to interpolate all grids
addpath SLFunctions
N = maxdeg; 
[x,w] = GaussQuad(N);
x_GL = acos(x)*180/pi - 90;
lon_GL = linspace(0,360,2*N+1);
lon_GL = lon_GL(1:end-1);

[lon_out,lat_out] = meshgrid(lon_GL,x_GL);

% Precompute legendre polynomials
P_lm = cell(N+1,1);
for l=0:N
    P_lm{l+1} = legendre(l,x,'norm');
end

% --------------------------------
% ICE
% --------------------------------

%% Pliocene disequilibrium
ice6g = importdata('ice_grid/Pliocene_ice.mat');
ice_time = importdata('ice_grid/Pliocene_timeka.mat');
ice_time = single(ice_time);
%% Present-day disequilibrium
% ice6g = importdata('ice_grid/Presday_diseq_ice.mat');
% ice_time = importdata('ice_grid/Presday_timeka.mat');
% ice_time = single(ice_time);

%%
ice_lat = importdata('ice_grid/ice_lat.mat');
ice_long = importdata('ice_grid/ice_long.mat');

ice_in = double(ice6g);

clear ice6g

for i = 1:length(ice_time)
    ice6g(i,:,:) = (ice_in(:,:,i)');
end

ice_in = ice6g;

ice = single(zeros(length(x_GL),length(lon_GL),length(ice_time)));
ice_time_new = zeros(size(ice_time));

ice_lat = [90; flipud(ice_lat); -90];
ice_long = [-0.5; ice_long; 360.5];

for i = 1:length(ice_time)

    % put onto on Gauss Legendre grid
    ice_nointerp = squeeze(ice_in(i,:,:));
    
    % add rows at top and bottom, and right
    ice_extended = [zeros(1,length(ice_long)-2); ice_nointerp; ...
        ice_nointerp(1,end)*ones(1,length(ice_long)-2)];
    
    ice_extended_2 = [ice_extended(:,end), ice_extended, ice_extended(:,1)];

    % interpolate ice masks on Gauss Legendre grid
    ice_interp = interp2(ice_long,ice_lat,ice_extended_2,lon_out,lat_out);
    
    ice(:,:,i) = ice_interp;
    ice_time_new(i) = ice_time(i);
end

%%

% time: ice_time_new
% ice model: ice

% ice -- on lon_out, lat_out
% ice_time_new -- old to young

% --------------------------------
% TOPOGRAPHY
% --------------------------------


% determine what index refers to present-day for the topography iteration
ind_pres = find(ice_time_new == max(ice_time_new));

% load preloaded etopo, which includes interpolated fields onto different
% sized Gauss Legendre Grids (hence avoiding interpolating twice)
load topo_SL

% interpolate topography grid onto Gauss Legendre Grid
if N == 64
    topo_pres = topo_bed_64 + ice(:,:,ind_pres);
elseif N == 128
    topo_pres = topo_bed_128 + ice(:,:,ind_pres);
elseif N == 256
    topo_pres = topo_bed_256 + ice(:,:,ind_pres);
elseif N == 512
    topo_pres = topo_bed_512 + ice(:,:,ind_pres);
elseif N == 1024
    topo_pres = topo_bed_1024 + ice(:,:,ind_pres);
else
    topo_pres = interp2(lon_topo,lat_topo,topo_bed,lon_out,lat_out) + ice(:,:,ind_pres);
end

oc_pres = sign_01(topo_pres);
ocpres_lm = sphere_har(oc_pres,maxdeg,N,P_lm);
oc_area = ocpres_lm(1);



%% Set up love number input

% prepare love numbers in suitable format and calculate T_lm and E_lm 
% to calculate the fluid case, switch h_el to h_fl, k_el to k_fl and same
% for tidal love numbers

% load SavedLN/prem.l96C.ump5.lm20.mat
% load SavedLN/prem.l96C.ump5.lm5.mat


h_lm = love_lm(h_el, maxdeg);
k_lm = love_lm(k_el, maxdeg);
h_lm_tide = love_lm(h_el_tide,maxdeg);
k_lm_tide = love_lm(k_el_tide,maxdeg);

E_lm = 1 + k_lm - h_lm;
T_lm = get_tlm(maxdeg);

E_lm_T = 1 + k_lm_tide - h_lm_tide;


% calculate betas
beta_l = cell(length(ice_time_new)-1,1);
beta_konly_l = cell(length(ice_time_new)-1,1);

for t_it = 2:length(ice_time_new)
    
    for n = 2:t_it-1
        
        beta = zeros(maxdeg, 1);
        for lm = 1:maxdeg
            num_mod = mode_found(lm);
            beta(lm) = sum((k_amp(lm,1:num_mod) - h_amp(lm,1:num_mod)) ...
                ./spoles(lm,1:num_mod).* (1 - exp(- spoles(lm,1:num_mod) ...
                * (-ice_time_new(t_it) + ice_time_new(n)))));
        end
        
        beta_l{t_it-1}(n-1,:) = [0; beta]; % add 0 LN

        % for rotation only needed for degree 2
        lm = 2;
        num_mod = mode_found(lm);
        beta_konly_l{t_it-1}(n-1) = sum((k_amp(lm,1:num_mod)) ...
                ./spoles(lm,1:num_mod).* (1 - exp(- spoles(lm,1:num_mod) ...
                * (-ice_time_new(t_it) + ice_time_new(n)))));

    end
end


% calculate tidal betas

beta_tide = cell(length(ice_time_new)-1,1);
beta_konly_tide = cell(length(ice_time_new)-1,1);

for t_it = 2:length(ice_time_new)
    
    for n = 2:t_it-1
        
        beta = zeros(maxdeg, 1);
        for lm = 1:maxdeg
            num_mod = mode_found(lm);
            beta(lm) = sum((k_amp_tide(lm,1:num_mod) - h_amp_tide(lm,1:num_mod)) ...
                ./spoles(lm,1:num_mod).* (1 - exp(- spoles(lm,1:num_mod) ...
                * (-ice_time_new(t_it) + ice_time_new(n)))));
            
        end
        
        beta_tide{t_it-1}(n-1,:) = [0; beta]; % add 0 LN
        
        % for rotation only needed for degree 2
        lm = 2;
        num_mod = mode_found(lm);
        beta_konly_tide{t_it-1}(n-1) = sum((k_amp_tide(lm,1:num_mod)) ...
                ./spoles(lm,1:num_mod).* (1 - exp(- spoles(lm,1:num_mod) ...
                * (-ice_time_new(t_it) + ice_time_new(n)))));

    end
end

% initiate mapping from l to lm
beta_counter = ones(size(h_lm));
l_it = 1;
for lm_it = 1:length(h_lm)
    if lm_it == l_it*(l_it+1)/2
        beta_counter(lm_it+1) = beta_counter(lm_it)+1;
        l_it = l_it+1;
    else
        beta_counter(lm_it+1) = beta_counter(lm_it);
    end
end


%% Solve sea level equation (after Kendall 2005, Dalca 2013 & Austermann et al. 2015)
tic
k_max = 10;   % maximum number of iterations
epsilon = 10^-4;%10^-4; % convergence criterion

topo_it_max = 3;   % maximum number of iterations %4 for to reproduce sam to 0.0xm
max_topo_diff = 1; % convergence criterion

% 0 = before
% j = after

% set up initial topography and ocean function
topo_initial = zeros(length(x_GL),length(lon_GL),topo_it_max+1);
topo_initial(:,:,1) = topo_pres - ice(:,:,ind_pres) + ice(:,:,1); % already includes ice, DT and sediments

% initial topography guess: topography is the same as present at every
% point in time; topography is a 3D vector; access topography at time x
% like this topo(:,:,x) [or for plotting squeeze(topo(:,:,x))]
topo = zeros(length(x_GL),length(lon_GL),length(ice_time_new));
for i = 2:length(ice_time_new)
    topo(:,:,i) = topo_pres - ice(:,:,ind_pres) + ice(:,:,i);
end


% initialize 
ice_corrected = ice;
sdelS_lm = zeros(length(ice_time_new),length(h_lm));

% initial values for convergence
conv_topo = 'not converged yet';

% TOPOGRAPHY ITERATION
for topo_it = 1:topo_it_max;
    
    switch conv_topo

        case 'converged!'

        case 'not converged yet'
            
        % initialize for each timestep
        delL_lm_prev = zeros(1,length(h_lm));
        delS_lm_prev = zeros(1,length(h_lm));
        TO_lm_prev = zeros(1,length(h_lm));
        delLa_lm_prev = zeros(1,length(h_lm));
        deli_00_prev = 0;
        sdelL_lm = zeros(length(ice_time_new)-1,length(h_lm));
        sdelLa_lm = zeros(length(ice_time_new)-1,length(h_lm));
        sdelI = zeros(length(ice_time_new)-1,3);
        sdelm = zeros(length(ice_time_new)-1,3);
        ESL = 0;

        % update new initial topography
        topo(:,:,1) = topo_initial(:,:,topo_it);

        % remove the corrected ice model and add initial ice model back on
        % this needs to be done to calculate the updated corrected ice model
        for i = 1:length(ice_time_new) 
            topo(:,:,i) = topo(:,:,i) - ice_corrected(:,:,i) + ice(:,:,i);
        end

        % recompute corrected ice model
        % do grounded ice check to calculate the corrected ice model
        for i = 1:length(ice_time_new)
            if include_ice_check == 'y'
                 % check ice model for floating ice
                 check1 = sign_01(-topo(:,:,i) + ice(:,:,i));
                 check2 = sign_01(+topo(:,:,i) - ice(:,:,i)) .* ...
                     (sign_01(-ice(:,:,i)*rho_ice - (topo(:,:,i) - ice(:,:,i))*rho_water));

                 ice_corrected(:,:,i) = check1.*ice(:,:,i) + check2.*ice(:,:,i);
            else
                % if the floating ice check is set to 'n' that don't change the
                % ice model
                 ice_corrected(:,:,i) = ice(:,:,i);
            end
        end

        % update all topographies with the new / corrected ice model
        for i = 1:length(ice_time_new) 
            topo(:,:,i) = topo(:,:,i) - ice(:,:,i) + ice_corrected(:,:,i);
        end

        % assign topography of time 0 and calculate ocean functions
        topo_0 = topo(:,:,1);
        oc_0 = sign_01(topo_0);
        oc0_lm = sphere_har(oc_0,maxdeg,N,P_lm);
        ocj_lm_prev = oc0_lm;
        

        % TIME ITERATION
        for t_it = 2:length(ice_time_new) % loop over time

            % Assign topography and ocean function of time t_it to the
            % index j
            topo_j = topo(:,:,t_it);
            oc_j = sign_01(topo_j);
            ocj_lm = sphere_har(oc_j,maxdeg,N,P_lm); 

            % calculate topography correction
            TO = topo_0.*(oc_j-oc_0);
            TO_lm = sphere_har(TO,maxdeg,N,P_lm);

            % calculate the change in ice model
            del_ice_corrected = ice_corrected(:,:,t_it) - ice_corrected(:,:,1);
            deli_lm = sphere_har(del_ice_corrected,maxdeg,N,P_lm);
            deli_lm_save(t_it) = deli_lm(1);
            % calculate the incremental increase in ice volume
            sdeli_00 = deli_lm(1) - deli_00_prev;

            % initial values for convergence
            conv = 'not converged yet';

            % SEA LEVEL EQUATION ITERATION
            for k = 1:k_max % loop for sea level and topography iteration

                switch conv

                    case 'converged!'

                    case 'not converged yet'

                    % set up initial guess for sea surface height change
                    if k == 1 && topo_it == 1
                        % initial guess of sea level change is just to distribute the
                        % ice over the oceans
                        % use slightly different initial guess than Kendall

                        sdelS_lm(t_it,:) = ocj_lm_prev/ocj_lm_prev(1)*...
                            (-rho_ice/rho_water*sdeli_00 + ...
                            TO_lm(1)-TO_lm_prev(1)) ...
                            - TO_lm - TO_lm_prev;
                    end

                    delS_lm = delS_lm_prev + sdelS_lm(t_it,:);

                    % calculate change in loading
                    % delL is total change in loading
                    delL_lm = rho_ice*deli_lm + rho_water*delS_lm;
                    % sdelL (small delta L) is incremental change in load -
                    % relative to last time step
                    sdelL_lm(t_it-1,:) = delL_lm - delL_lm_prev;

                    
                    % calculate viscous contribution

                    % beta contains the viscous love numbers for time t_it,
                    % row index goes over the time increments, column
                    % index goes over lm
                    if t_it == 2
                        V_lm = zeros(size(T_lm));
                    else
                        for lm_it = 1:length(h_lm)
                            V_lm(lm_it) = beta_l{t_it-1}(:,beta_counter(lm_it))'...
                                * sdelL_lm(1:t_it-2,lm_it);
                        end
                    end


                    % calculate contribution from rotation
                    if include_rotation == 'y'
                        [delLa_lm, sdelI, sdelm] = calc_rot_visc(delL_lm,...
                            k_el(2),k_el_tide(2),t_it,...
                            beta_konly_l, beta_konly_tide,...
                            sdelI, sdelm);
                        sdelLa_lm(t_it-1,:) = delLa_lm - delLa_lm_prev;
                        
                        if t_it == 2
                            V_lm_T = zeros(size(T_lm));
                        else
                            for lm_it = 1:6 % don't need to loop over all degrees 
                                V_lm_T(lm_it) = beta_tide{t_it-1}(:,beta_counter(lm_it))'...
                                    * sdelLa_lm(1:t_it-2,lm_it);
                            end
                        end   
                        
                        % calculate sea level perturbation
                        % add ice and sea level and multiply with love numbers
                        % DT doesn't load!
                        delSLcurl_lm_fl = E_lm .* T_lm .* delL_lm + T_lm .* V_lm + ...
                           1/g*E_lm_T.*delLa_lm + 1/g*V_lm_T;
                    
                    % if don't include rotation 
                    else
                        delSLcurl_lm_fl = E_lm .* T_lm .* delL_lm + ...
                            T_lm .* V_lm;
                    end
                    

                    % convert to spherical harmonics and subtract terms that are part
                    % of the topography to get the 'pure' sea level change
                    delSLcurl_fl = inv_sphere_har(delSLcurl_lm_fl,maxdeg,N,P_lm);
                    delSLcurl = delSLcurl_fl - del_ice_corrected;


                    % compute and decompose RO
                    RO = delSLcurl.*oc_j;
                    RO_lm = sphere_har(RO,maxdeg,N,P_lm);

                    % calculate eustatic sea level perturbation (delta Phi / g)
                    delPhi_g = 1/ocj_lm(1) * (- rho_ice/rho_water*deli_lm(1) ...
                        - RO_lm(1) + TO_lm(1));


                    sdelS_lm_new = RO_lm + delPhi_g.*ocj_lm - TO_lm ...
                        - delS_lm_prev;


                    % calculate convergence criterion chi
                    chi = abs((sum(abs(sdelS_lm_new)) - sum(abs(sdelS_lm(t_it,:)))) / ...
                        sum(abs(sdelS_lm(t_it,:))) );


                    % check convergence against the value epsilon
                    % If converged, set the variable conv to 'converged!' so that the
                    % calculation exits the loop. If not converged iterate again.
                    if chi < epsilon;
                        conv = 'converged!';
                        disp(['Finished time ' num2str(ice_time_new(t_it))...
                        'kyr. Number of iterations ' num2str(k) '. delphi is ' num2str(delPhi_g)])
                       % disp(['Converged after iteration ' num2str(k) '. Chi was ' num2str(chi) '.'])
                    elseif chi < epsilon && k == k_max;
                        conv = 'not converged yet';
                        disp(['Finished time ' num2str(ice_time_new(t_it))...
                        'kyr. Run has not converged. Chi is  ' num2str(chi)])
                    else
                        conv = 'not converged yet';
                        %disp(['Finished iteration ' num2str(k) '. Chi was ' num2str(chi) '.'])
                    end

                    % update sea sea surface height
                    sdelS_lm(t_it,:) = sdelS_lm_new;

                end

            end

            delS_lm_prev = delS_lm;
            TO_lm_prev = TO_lm;
            delL_lm_prev = delL_lm;
            deli_00_prev = deli_lm(1);
            ESL(t_it) = deli_lm(1)/oc_area * rho_ice/rho_water;
            
            %%
         
            
            if include_rotation == 'y'
                delLa_lm_prev = delLa_lm;
            end

            % calculate overall perturbation of sea level over oceans
            % (spatially varying field and constant offset)
            delSL = delSLcurl + delPhi_g;

            % write in topography for next iteration
            topo(:,:,t_it) = - delSL + topo_0;
            ocj_lm_prev = ocj_lm;


        end
        %ind_present = find(ice_time_new == 0);
        ind_present = find(ice_time_new == max(ice_time));
        
        topo_pres_ice_corrected = topo_pres - ice(:,:,ind_present) + ice_corrected(:,:,ind_present);

        topo_diff = max(max(abs(topo(:,:,ind_present) - topo_pres_ice_corrected)));

        if topo_diff < max_topo_diff;
            conv_topo = 'converged!';
            disp(['Converged!! Number of topo iterations ' num2str(topo_it) ...
                '. Topo_diff is ' num2str(topo_diff)])
        else
            conv_topo = 'not converged yet';
            disp(['Not converged. Number of topo iterations ' num2str(topo_it) ...
                '. Topo_diff is ' num2str(topo_diff)])
        end

    end
    
    % update initial topography
    topo_initial(:,:,topo_it+1) = topo_pres_ice_corrected - (topo(:,:,ind_present) - topo(:,:,1));
    
    break
    
end

%% for Pliocene disequilibrium 
ind_present = find(ice_time_new == max(ice_time));
%% for present-day disequilibrium
% ind_present = find(ice_time_new == 0);
%%

RSL = zeros(size(topo));
for i = 1:length(ice_time_new)
    RSL(:,:,i) = (topo(:,:,ind_present) - ice_corrected(:,:,ind_present)) - ...
        (topo(:,:,i) - ice_corrected(:,:,i));
end

%% fixed ocean (ice based)

f_oc_mask = sign_01(topo(:,:,1));
f_oc_area_temp = f_oc_mask;
f_oc_area_lm = sphere_har(f_oc_area_temp,maxdeg,N,P_lm);
f_oc_prct = f_oc_area_lm(1);

for i = 1:length(topo(1,1,:))    
    ESL_f_area(i) = deli_lm_save(i)./f_oc_prct * (rho_ice/rho_water);
end


ESL_f_area = -(ESL_f_area - ESL_f_area(1));
