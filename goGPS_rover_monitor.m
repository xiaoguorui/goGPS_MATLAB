function goGPS_rover_monitor(filerootOUT, protocol)

% SYNTAX:
%   goGPS_rover_monitor(filerootOUT, protocol)
%
% INPUT:
%   filerootOUT = output file prefix
%   protocol    = protocol verctor (0:Ublox, 1:Fastrax, 2:SkyTraq)
%
% DESCRIPTION:
%   Monitor of receiver operations: stream reading, data visualization 
%   and output data saving. Simulataneous monitor of different receivers,
%   also including different protocols.

%----------------------------------------------------------------------------------------------
%                           goGPS v0.2.0 beta
%
% Copyright (C) 2009-2011 Mirko Reguzzoni, Eugenio Realini
%----------------------------------------------------------------------------------------------
%
%    This program is free software: you can redistribute it and/or modify
%    it under the terms of the GNU General Public License as published by
%    the Free Software Foundation, either version 3 of the License, or
%    (at your option) any later version.
%
%    This program is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%    GNU General Public License for more details.
%
%    You should have received a copy of the GNU General Public License
%    along with this program.  If not, see <http://www.gnu.org/licenses/>.
%----------------------------------------------------------------------------------------------

global COMportR
global rover

%------------------------------------------------------
% read protocol parameters
%------------------------------------------------------

nrec = length(protocol);
prot_par = cell(nrec,1);

for r = 1 : nrec
    if (protocol(r) == 0)
        prot_par{r} = param_ublox;
    elseif (protocol(r) == 1)
        prot_par{r} = param_fastrax;
    elseif (protocol(r) == 2)
        prot_par{r} = param_skytraq;
    end
end

%------------------------------------------------------
% initialization
%------------------------------------------------------

Eph = cell(nrec,1);
iono = cell(nrec,1);

for r = 1 : nrec

    % ephemerides
    Eph{r} = zeros(29,32);

    % ionosphere parameters
    iono{r} = zeros(8,1);
end

%------------------------------------------------------
% data file creation
%------------------------------------------------------

fid_rover = cell(nrec,1);
fid_obs = cell(nrec,1);
fid_eph = cell(nrec,1);
fid_nmea = cell(nrec,1);

for r = 1 : nrec

    recname = [prot_par{r}{1,1} num2str(r)];

    % rover binary stream (uint8)
    fid_rover{r} = fopen([filerootOUT '_' recname '_rover_00.bin'],'w+');

    % input observations
    %   time_GPS --> double, [1,1]  --> zeros(1,1)
    %   time_M   --> double, [1,1]  --> zeros(1,1)
    %   time_R   --> double, [1,1]
    %   pr_M     --> double, [32,1] --> zeros(32,1)
    %   pr_R     --> double, [32,1]
    %   ph_M     --> double, [32,1] --> zeros(32,1)
    %   ph_R     --> double, [32,1]
    %   snr_M    --> double, [32,1] --> zeros(32,1)
    %   snr_R    --> double, [32,1]
    fid_obs{r} = fopen([filerootOUT '_' recname '_obs_00.bin'],'w+');

    % input ephemerides
    %   timeGPS  --> double, [1,1]  --> zeros(1,1)
    %   Eph      --> double, [29,32]
    fid_eph{r} = fopen([filerootOUT '_' recname '_eph_00.bin'],'w+');

    % nmea sentences
    fid_nmea{r} = fopen([filerootOUT '_' recname '_NMEA.txt'],'wt');
end

%------------------------------------------------------
% creation of the rover connections
%------------------------------------------------------

rover = cell(nrec,1);

for r = 1 : nrec

    % find a serial port object.
    obj1 = instrfind('Type', 'serial', 'Port', COMportR{r}, 'Tag', '');

    % if a serial object already exists, delete it before creating a new one
    if ~isempty(obj1)
        delete(obj1);
    end

    % serial object creation
    rover{r} = serial (COMportR{r},'BaudRate',prot_par{r}{2,1});
    set(rover{r},'InputBufferSize',prot_par{r}{3,1});
    if (protocol(r) == 0)
        set(rover{r},'FlowControl','hardware');
        set(rover{r},'RequestToSend','on');
    end
end

%------------------------------------------------------
% set receiver configuration
%------------------------------------------------------

for r = 1 : nrec

    % u-blox configuration
    if (protocol(r) == 0)

        %visualization
        fprintf('\n');
        fprintf('CONFIGURATION (u-blox n.%d)\n',r);

        % only one connection can be opened in writing mode
        fopen(rover{r});

        [rover{r}, reply_save] = configure_ublox(rover{r}, COMportR{r}, prot_par{r}, 1);

        % temporary connection closure (for other receiver setup)
        fclose(rover{r});

    % fastrax configuration
    elseif (protocol(r) == 1)

        %visualization
        fprintf('\n');
        fprintf('CONFIGURATION (fastrax n.%d)\n',r);
        
        % only one connection can be opened in writing mode
        fopen(rover{r});
        
        [rover{r}] = configure_fastrax(rover{r}, COMportR{r}, prot_par{r}, 1);

        % temporary connection closure (for other receiver setup)
        fclose(rover{r});

    % skytraq configuration
    elseif (protocol(r) == 2)

        %visualization
        fprintf('\n');
        fprintf('CONFIGURATION (skytraq n.%d)\n',r);
        
        % only one connection can be opened in writing mode
        fopen(rover{r});

        [rover{r}] = configure_skytraq(rover{r}, COMportR{r}, prot_par{r}, 1);

        % temporary connection closure (for other receiver setup)
        fclose(rover{r});
    end
end

%------------------------------------------------------
% open rover connections
%------------------------------------------------------

for r = 1 : nrec
    fopen(rover{r});
end

%------------------------------------------------------
% absolute time startup
%------------------------------------------------------

tic

%------------------------------------------------------
% log file initialization
%------------------------------------------------------

delete([filerootOUT '_log.txt']);
diary([filerootOUT '_log.txt']);
diary on

%------------------------------------------------------
% read header package (transmission start)
%------------------------------------------------------

%visualization
fprintf('\n');
fprintf('LOCK-PHASE (HEADER PACKAGE)\n');

%initialization
test = ones(nrec,1);
rover_1 = zeros(nrec,1);
rover_2 = zeros(nrec,1);

%starting epoch determination
while (sum(test) > 0)

    %starting time
    current_time = toc;

    for r = 1 : nrec

        %serial port checking
        rover_1(r) = get(rover{r},'BytesAvailable');
        pause(0.05);
        rover_2(r) = get(rover{r},'BytesAvailable');

        %test condition
        test(r) = (rover_1(r) ~= rover_2(r)) | (rover_1(r) == 0);% | (rover_1(r) < prot_par{r}{4,1});

        %visualization
        fprintf([prot_par{r}{1,1} '(' num2str(r) ')' ': %7.4f sec (%4d bytes --> %4d bytes)\n'], current_time, rover_1(r), rover_2(r));
    end
end

%clear serial ports (data not decoded)
for r = 1 : nrec
    data_rover = fread(rover{r},rover_1(r),'uint8'); %#ok<NASGU>
end

%--------------------------------------------------------
% read 1st message (used only for synchronization)
%--------------------------------------------------------

%visualization
fprintf('\n');
fprintf('LOCK-PHASE (FIRST DATA PACKAGE)\n');

%initialization
test = ones(nrec,1);
rover_1 = zeros(nrec,1);
rover_2 = zeros(nrec,1);

%starting epoch determination
while (sum(test) > 0)

    %starting time
    current_time = toc;
    
    for r = 1 : nrec

        %serial port checking
        rover_1(r) = get(rover{r},'BytesAvailable');
        pause(0.05);
        rover_2(r) = get(rover{r},'BytesAvailable');

        %test condition
        test(r) = (rover_1(r) ~= rover_2(r)) | (rover_1(r) == 0);% | (rover_1(r) < prot_par{r}{4,1});

        %visualization
        fprintf([prot_par{r}{1,1} '(' num2str(r) ')' ': %7.4f sec (%4d bytes --> %4d bytes)\n'], current_time, rover_1(r), rover_2(r));
    end
end

%clear the serial port (data not decoded)
for r = 1 : nrec
    data_rover = fread(rover{r},rover_1(r),'uint8'); %#ok<NASGU>
end

%set the starting time
safety_lag = 0.1;                       %safety lag on ROVER data reading
start_time = current_time-safety_lag;   %starting time

%--------------------------------------------------------
% message polling
%--------------------------------------------------------

for r = 1 : nrec
    if (protocol(r) == 0)
        %poll available ephemerides
        ublox_poll_message(rover{r}, 'AID', 'EPH', 0);
        %wait for asynchronous write to finish
        pause(0.1);
        ublox_poll_message(rover{r}, 'AID', 'HUI', 0);
        %wait for asynchronous write to finish
        pause(0.1);
    elseif (protocol(r) == 2)
        %poll available ephemerides
        skytraq_poll_message(rover{r}, '30', 0);
        %wait for asynchronous write to finish
        pause(0.1);
    end
end

%poll flags
eph_polled = 1;
hui_polled = 1;

%--------------------------------------------------------
% data reading and saving
%--------------------------------------------------------

%visualization
fprintf('\n');
fprintf('ACQUISITION-PHASE\n');

%counter initialization
t = zeros(nrec,1);

%loop control initialization
f1 = figure;
s1 = get(0,'ScreenSize');
set(f1, 'position', [s1(3)-240-20 s1(4)-80-40 240 80], 'menubar', 'none', 'name', 'UBLOX monitor');
h1 = uicontrol(gcf, 'style', 'pushbutton', 'position', [80 20 80 40], 'string', 'STOP', ...
    'callback', 'setappdata(gcf, ''run'', 0)'); %#ok<NASGU>
flag = 1;
setappdata(gcf, 'run', flag);

%for Fastrax
tick_TRACK = 0;

%for SkyTraq
IOD_time = -1;

%infinite loop
while flag

    %time reading (relative to start_time)
    current_time = toc;

    for r = 1 : nrec

        %serial port checking
        rover_1 = get(rover{r},'BytesAvailable');
        pause(0.05);
        rover_2 = get(rover{r},'BytesAvailable');

        %test if the package writing is finished
        if (rover_1 == rover_2) & (rover_1 ~= 0)

            data_rover = fread(rover{r},rover_1,'uint8');     %serial port reading
            fwrite(fid_rover{r},data_rover,'uint8');          %transmitted stream save
            data_rover = dec2bin(data_rover,8);            %conversion to binary (N x 8bit matrix)
            data_rover = data_rover';                      %transpose (8bit x N matrix)
            data_rover = data_rover(:)';                   %conversion to string (8N bit vector)

            if (protocol(r) == 0)
                [cell_rover, nmea_sentences] = decode_ublox(data_rover);
            elseif (protocol(r) == 1)
                [cell_rover] = decode_fastrax_it03(data_rover);
                nmea_sentences = [];
            elseif (protocol(r) == 2)
                [cell_rover] = decode_skytraq(data_rover);
                nmea_sentences = [];
            end

            %read data type
            type = '';

            %data type counters
            nRAW = 0;
            nEPH = 0;
            nHUI = 0;
            nTRACK  = 0;
            nTIM = 0;

            for i = 1 : size(cell_rover,2)

                %Tracking message data save (TRACK)
                if (strcmp(cell_rover{1,i},prot_par{r}{6,2}))

                    tick_TRACK    = cell_rover{2,i}(1);
                    phase_TRACK   = cell_rover{3,i}(:,6);
                    nTRACK = nTRACK + 1;

                    type = [type prot_par{r}{6,2} ' '];

                %Timing/raw message data save (RXM-RAW | PSEUDO)
                elseif (strcmp(cell_rover{1,i},prot_par{r}{1,2}))

                    time_R = cell_rover{2,i}(1);
                    week_R = cell_rover{2,i}(2);
                    ph_R   = cell_rover{3,i}(:,1);
                    pr_R   = cell_rover{3,i}(:,2);
                    dop_R  = cell_rover{3,i}(:,3);
                    snr_R  = cell_rover{3,i}(:,6);

                    %u-blox specific fields
                    if (protocol(r) == 0)
                        qual_R = cell_rover{3,i}(:,5);
                        lock_R = cell_rover{3,i}(:,7);
                        nRAW = nRAW + 1;
                    end

                    %Fastrax specific fields
                    if (protocol(r) == 1)
                        tick_PSEUDO = cell_rover{2,i}(4);
                        ObsFlags_R  = cell_rover{3,i}(:,5);
                        Corr_R      = cell_rover{3,i}(:,7);
                        LDO_R       = cell_rover{3,i}(:,8);
                        RangeEE_R   = cell_rover{3,i}(:,9); %#ok<NASGU>
                        RateEE_R    = cell_rover{3,i}(:,10); %#ok<NASGU>
                        EpochCount  = cell_rover{3,i}(:,11);
                        % Synchronize PSEUDO and TRACK
                        if (tick_PSEUDO == tick_TRACK)
                            %manage phase without code
                            ph_R(abs(pr_R) > 0) = phase_TRACK(abs(pr_R) > 0);
                        else
                            ph_R = zeros(32,1);
                        end
                        nRAW = nRAW + 1;
                    end

                    %manage phase without code
                    ph_R(abs(pr_R) == 0) = 0;

                    %manage "nearly null" data
                    ph_R(abs(ph_R) < 1e-100) = 0;

                    %counter increment
                    t(r) = t(r)+1;

                    %satellites with ephemerides available
                    satEph = find(sum(abs(Eph{r}))~=0);

                    %satellites with observations available
                    satObs = find(pr_R(:,1) ~= 0);

                    %if all the visible satellites ephemerides have been transmitted
                    %and the total number of satellites is >= 4
                    if (ismember(satObs,satEph)) & (length(satObs) >= 4)

                        %data save
                        fwrite(fid_obs{r}, [0; 0; time_R; week_R; zeros(32,1); pr_R; zeros(32,1); ph_R; dop_R; zeros(32,1); snr_R; zeros(3,1); iono{r}(:,1)], 'double');
                        fwrite(fid_eph{r}, [0; Eph{r}(:)], 'double');
                    end

                    type = [type prot_par{r}{1,2} ' '];

                %Timing message data save (MEAS_TIME)
                elseif (strcmp(cell_rover{1,i},prot_par{r}{4,2}))

                    IOD_time = cell_rover{2,i}(1);
                    time_stq = cell_rover{2,i}(3);
                    week_stq = cell_rover{2,i}(2);

                    type = [type prot_par{r}{4,2} ' '];
                    nTIM = nTIM + 1;

                %Raw message data save (RAW_MEAS)
                elseif (strcmp(cell_rover{1,i},prot_par{r}{5,2}))

                    IOD_raw = cell_rover{2,i}(1);
                    if (IOD_raw == IOD_time)
                        time_R = time_stq;
                        week_R = week_stq;
                        pr_R = cell_rover{3,i}(:,3);
                        ph_R = cell_rover{3,i}(:,4);
                        snr_R = cell_rover{3,i}(:,2);
                        dop_R = cell_rover{3,i}(:,5);

                        %manage phase without code
                        ph_R(abs(pr_R) < 1e-100) = 0;
                        
                        %manage "nearly null" data
                        pr_R(abs(pr_R) < 1e-100) = 0;
                        ph_R(abs(ph_R) < 1e-100) = 0;

                        type = [type prot_par{r}{5,2} ' '];
                        nRAW = nRAW + 1;

                        %counter increment
                        t(r) = t(r)+1;
                        
                        %satellites with ephemerides available
                        satEph = find(sum(abs(Eph{r}))~=0);
                        
                        %satellites with observations available
                        satObs = find(pr_R(:,1) ~= 0);
                        
                        %if all the visible satellites ephemerides have been transmitted
                        %and the total number of satellites is >= 4
                        if (ismember(satObs,satEph)) & (length(satObs) >= 4)
                            
                            %data save
                            fwrite(fid_obs{r}, [0; 0; time_R; week_R; zeros(32,1); pr_R; zeros(32,1); ph_R; dop_R; zeros(32,1); snr_R; zeros(3,1); iono{r}(:,1)], 'double');
                            fwrite(fid_eph{r}, [0; Eph{r}(:)], 'double');
                        end
                    end

                %Hui message data save (AID-HUI)
                elseif (strcmp(cell_rover{1,i},prot_par{r}{3,2}))

                    %ionosphere parameters
                    iono{r}(:, 1) = cell_rover{3,i}(9:16);

                    if (nHUI == 0)
                        type = [type prot_par{r}{3,2} ' '];
                    end
                    nHUI = nHUI + 1;

                %Eph message data save (AID-EPH | FTX-EPH | GPS_EPH)
                elseif (strcmp(cell_rover{1,i},prot_par{r}{2,2}))

                    %satellite number
                    sat = cell_rover{2,i}(1);

                    if (~isempty(sat) & sat > 0)
                        Eph{r}(:, sat) = cell_rover{2,i}(:);
                    end

                    if (nEPH == 0)
                        type = [type prot_par{r}{2,2} ' '];
                    end
                    nEPH = nEPH + 1;

                end

            end

            if (~isempty(nmea_sentences))
                n = size(nmea_sentences,1);
                for i = 1 : n
                    fprintf(fid_nmea{r}, '%s', char(nmea_sentences(i,1)));
                end

                type = [type 'NMEA '];
            end

            %----------------------------------

            %visualization
            fprintf('\n');
            fprintf('---------------------------------------------------\n')
            fprintf([prot_par{r}{1,1} '(' num2str(r) ')' ': %7.4f sec (%4d bytes --> %4d bytes)\n'], current_time-start_time, rover_1, rover_2);
            fprintf('MSG types: %s\n', type);

            %visualization (Timing/raw information)
            if (nRAW > 0)
                sat_pr = find(pr_R ~= 0);       %satellites with code available
                sat_ph = find(ph_R ~= 0);       %satellites with phase available
                sat = union(sat_pr,sat_ph);     %satellites with code or phase available

                if (i < length(time_R)), fprintf(' DELAYED\n'); else fprintf('\n'); end
                fprintf('Epoch %3d:  GPStime=%d:%.3f (%d satellites)\n', t(r), week_R, time_R, length(sat));
                for j = 1 : length(sat)
                    if (protocol(r) == 0)
                        fprintf('   SAT %02d:  P1=%11.2f  L1=%12.2f  D1=%7.1f  QI=%1d  SNR=%2d  LOCK=%1d\n', ...
                            sat(j), pr_R(sat(j)), ph_R(sat(j)), dop_R(sat(j)), qual_R(sat(j)), snr_R(sat(j)), lock_R(sat(j)));
                    elseif (protocol(r) == 1)
                        % fprintf('   SAT %02d:  P1=%11.2f  L1=%12.2f  D1=%7.1f  QI=%1d  SNR=%2d  LOCK=%1d\n', ...
                        %     sat(j), pr_R(sat(j)), ph_R(sat(j)), dop_R(sat(j)),
                        %     qual_R(sat(j)), snr_R(sat(j)), lock_R(sat(j)));
                        fprintf('   SAT %02d:  P1=%11.2f  L1=%13.4f  D1=%7.1f  SNR=%2d  FLAG=%5d  CORR=%5d  LDO=%5d  ECnt=%6d \n', ...
                            sat(j), pr_R(sat(j)), ph_R(sat(j)), dop_R(sat(j)), snr_R(sat(j)), ObsFlags_R(sat(j)), Corr_R(sat(j)), LDO_R(sat(j)), ...
                            EpochCount(sat(j)));
                    elseif (protocol(r) == 2)
                        fprintf('   SAT %02d:  P1=%11.2f  L1=%12.2f  D1=%7.1f  SNR=%2d\n', ...
                            sat(j), pr_R(sat(j)), ph_R(sat(j)), dop_R(sat(j)), snr_R(sat(j)));
                    end
                end
            end

            %visualization (AID-HUI information)
            if (nHUI > 0)
                fprintf('Ionosphere parameters: ');
                if (sum(iono{r}) ~= 0)
                    fprintf('\n');
                    fprintf('    alpha0: %12.4E\n', iono{r}(1));
                    fprintf('    alpha1: %12.4E\n', iono{r}(2));
                    fprintf('    alpha2: %12.4E\n', iono{r}(3));
                    fprintf('    alpha3: %12.4E\n', iono{r}(4));
                    fprintf('    beta0 : %12.4E\n', iono{r}(5));
                    fprintf('    beta1 : %12.4E\n', iono{r}(6));
                    fprintf('    beta2 : %12.4E\n', iono{r}(7));
                    fprintf('    beta3 : %12.4E\n', iono{r}(8));
                else
                    fprintf('not sent\n');
                end
            end

            %visualization (AID-EPH information)
            if (nEPH > 0)
                sat = find(sum(abs(Eph{r}))>0);
                fprintf('Eph: ');
                for i = 1 : length(sat)
                    fprintf('%d ', sat(i));
                end
                fprintf('\n');
            end

            %poll a new ephemeris message every 10 epochs
            if (mod(current_time-start_time,10) < 1)
                if (eph_polled == 0)
                    if (protocol(r) == 0)
                        ublox_poll_message(rover{r}, 'AID', 'EPH', 0);
                        eph_polled = 1;
                    elseif (protocol(r) == 2)
                        skytraq_poll_message(rover{r}, '30', 0);
                        eph_polled = 1;
                    end
                end
            else
                eph_polled = 0;
            end

            %wait for asynchronous write to finish
            pause(0.1);

            %poll a new AID-HUI message every 60 epochs
            if (mod(current_time-start_time,60) < 1)
                if (hui_polled == 0)
                    if (protocol(r) == 0)
                        ublox_poll_message(rover{r}, 'AID', 'HUI', 0);
                        hui_polled = 1;
                    end
                end
            else
                hui_polled = 0;
            end
        end
    end

    %----------------------------------

    %test if the cycle execution has ended
    flag = getappdata(gcf, 'run');
    drawnow

end

%------------------------------------------------------
% close rover connections
%------------------------------------------------------

for r = 1 : nrec
    fclose(rover{r});
end

%------------------------------------------------------
% restore receiver original configuration
%------------------------------------------------------

for r = 1 : nrec

    % u-blox configuration
    if (protocol(r) == 0)
        
        %visualization
        fprintf('\n');
        fprintf('CONFIGURATION (u-blox n.%d)\n',r);

        % only one connection can be opened in writing mode
        fopen(rover{r});

        % load u-blox saved configuration
        if (reply_save)
            fprintf('Restoring saved u-blox receiver configuration...\n');

            reply_load = ublox_CFG_CFG(rover{r}, 'load');
            tries = 0;

            while (~reply_load)
                tries = tries + 1;
                if (tries > 3)
                    disp('It was not possible to reload the receiver previous configuration.');
                    break
                end
                reply_load = ublox_CFG_CFG(rover{r}, 'load');
            end
        end

        % connection closure
        fclose(rover{r});

    end
end

%------------------------------------------------------
% close files
%------------------------------------------------------

for r = 1 : nrec

    %data files closing
    fclose(fid_rover{r});
    fclose(fid_obs{r});
    fclose(fid_eph{r});
    fclose(fid_nmea{r});
end

%log file closing
diary off

%------------------------------------------------------
% tasks at the end of the cycle
%------------------------------------------------------

%figure closing
close(f1);

%------------------------------------------------------
% RINEX conversion
%------------------------------------------------------

%dialog
selection = questdlg('Do you want to decode the binary streams and create RINEX files?',...
    'Request Function',...
    'Yes','No','Yes');
switch selection,
    case 'Yes',
        %visualization
        fprintf('\n');
        fprintf('RINEX CONVERSION\n');
        
        for r = 1 : nrec
            recname = [prot_par{r}{1,1} num2str(r)];
            streamR2RINEX([filerootOUT '_' recname],[filerootOUT '_' recname '_rover']);
        end
end