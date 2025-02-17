function [BER,ToA_sq_err, phase_offset_sq_err, CFO_rough_sq_err] = calculate_global_data_3_1(ch, am_symbols ,cp_length, LOS,...
    bitspersymbol,... %1)
    SNR_db,... %2)
    am_ant,... %3) - also included with ch, but just for completeness
    ToA_uncertainty,... %4)
    add_pilots_bool, pilot_percentage,... %5)
    CFO, rough_correction_enabled) %6)
%MIMO_CALCULATE_GLOBAL_DATA Implementing a total simulation of the MIMO
%channel, with time uncertainty, CFO, the possibility of pilots, and more!
%   TODO write detailed explanation

% addpath functions
%calculate length of data further down
am_bits_original = am_symbols * bitspersymbol;                               %Total number of bits to be transmitted at the transmitter (bits)
am_blocks_original = am_symbols/ch.Q;
am_bits_padded = am_bits_original + cp_length*am_blocks_original*bitspersymbol;
am_symbols_padded = am_symbols + cp_length*am_blocks_original;

%generate random bit stream as input signal
bits = randi([0,1],am_bits_original,1);
Symbols = QAM_modulation(bits, bitspersymbol);
if add_pilots_bool == 1
    pilot_symbol = QAM_modulation(ones(bitspersymbol,1),bitspersymbol);
    pilot_amount_per_row  = floor(ch.Q*pilot_percentage);
    pilot_indices_row = floor(linspace(1,ceil(ch.Q*(pilot_amount_per_row-1)/pilot_amount_per_row), pilot_amount_per_row))+1;
    for signal_row_index = 0:floor(length(Symbols)/ch.Q)-1
        Symbols(pilot_indices_row+ch.Q*signal_row_index) = pilot_symbol;
    end
    bits = QAM_demodulation(Symbols,bitspersymbol);
end
symbols = zeros(1,am_symbols);       
for i = 1:am_blocks_original
    begin_index = (i-1)*ch.Q + 1;
    end_index = i*ch.Q;
    % OFDM: IFFT
    symbols(begin_index:end_index) = ifft(Symbols(begin_index:end_index));
    %symbols(begin_index) = 0;
end

%add cp_padding
symbols_padded = zeros(1, am_symbols_padded);
if cp_length == 0
    symbols_padded = symbols;
else
    for i = 1:am_blocks_original
         begin_index = (i-1)*ch.Q + 1;
         end_index = i*ch.Q;   
         symbols_padded_start = (i-1)*(ch.Q + cp_length) + 1;
         symbols_padded_end = (i)*(ch.Q + cp_length);
         symbols_padded(symbols_padded_start:symbols_padded_start + cp_length - 1) = symbols(end_index-cp_length + 1: end_index);
         symbols_padded(symbols_padded_start + cp_length : symbols_padded_end) = symbols(begin_index: end_index);
         %symbols_padded(symbols_padded_start) = 0;
    end
end

%add ToA_prefix padding in front of symbol chain
if(ToA_uncertainty ~= 1)
    ToA_prep_signal = generate_ToA_est_signal(ch.Q,cp_length,bitspersymbol, 1);
    ToA_prep_blocks = length(ToA_prep_signal)/(ch.Q+cp_length) - am_blocks_original;
    symbols_padded = [ToA_prep_signal, symbols_padded];
end
am_blocks_padded = length(symbols_padded)/(ch.Q+cp_length);
am_symbols_padded = (ch.Q+cp_length)*am_blocks_padded;
am_bits_padded = bitspersymbol*am_symbols_padded;
%-------------------


%% the wideband way---------------------------------------
% if LOS == 1
%     [H_current, ~, ~] = getWideBand(ch); % simulates narrow band mimo channel
% else
%     [~, H_current, ~] = getWideBand(ch);
% end
% h_current = ifft(H_current);
% %cut from LOS peak to hard cutoff
% if LOS == 1
%     time_bin = 1/ch.B;
%     max_delay_index = floor(ch.path_params.max_delay / time_bin);
%     [~, LOS_index] = max(h_current);
%     h_current = h_current(LOS_index: max_delay_index);
%     H_current = fft(h_current, ch.Q);
% end
% 
% r_noiseless = conv(symbols_padded, h_current);
% %cut off cyclic prefix + tail
% if(length(r_noiseless) ~= length(symbols_padded))
%     boot_cutoff_length = length(h_current);
%     r_noiseless = r_noiseless(1:end-boot_cutoff_length+1);
% end
%% end of the wideband way-----------------------------------
 r_noiseless = symbols_padded;

time_bin = 1/ch.B;
r_noiseless_CFO_added = add_CFO(r_noiseless,CFO,time_bin);
r_noiseless_length = size(r_noiseless,2);

% add time uncertainty
ToA_est_signal = generate_ToA_est_signal(ch.Q,cp_length,bitspersymbol, 0);
if(ToA_uncertainty ~= 1)
%     r_noiseless_time_uncertain = zeros(ch.Nrx,ToA_uncertainty*r_noiseless_length);
    r_noiseless_time_uncertain = zeros(1,ToA_uncertainty*r_noiseless_length);
    random_index = floor(rand*(ToA_uncertainty-1)*r_noiseless_length);
    r_noiseless_time_uncertain(:,random_index:random_index+r_noiseless_length-1) = r_noiseless_CFO_added;
    r_time_uncertain = awgn(r_noiseless_time_uncertain,SNR_db, 'measured');
    %simple solution: taking the mean of all incoming signals
    r_time_uncertain_deMIMO = mean(r_time_uncertain,1);
    [time_acq_result, time_acq_lags] = xcorr(r_time_uncertain_deMIMO, ToA_est_signal);
%     figure
%     plot(time_acq_lags,time_acq_result);
%     title("Correlation between known preamble and noisy singal","with ToA-uncertainty = " + num2str(ToA_uncertainty))
%     xlabel("symbol index")
%     ylabel("R_{ToA}")
    [~,peak_indices] = maxk(time_acq_result,2,'ComparisonMethod','abs');
    peak_indices = sort(peak_indices);
    est_offset = time_acq_lags(peak_indices(1))-cp_length+1;
    r = r_time_uncertain(:,est_offset+2*(ch.Q+cp_length):est_offset+r_noiseless_length-1); %cut off prefix further
    CFO_est_signal = r_time_uncertain(:,est_offset:est_offset+2*(ch.Q+cp_length)-1);
else
    r = awgn(r_noiseless_CFO_added,SNR_db, 'measured');
%     r = r_noiseless_CFO_added; %DEBUG ONLY
    est_offset = 1; %just the first index
    random_index = 1;
    CFO_est_signal = awgn([ToA_est_signal ToA_est_signal], SNR_db, 'measured');
end

%NEW: CFO rough correction

% if SNR_db > 10
%     disp("debug break");
% end

if rough_correction_enabled == 1
    % idea: take the mean over the est_signal
    p_1 = CFO_est_signal(:,1:ch.Q+cp_length);
    p_2 = CFO_est_signal(:,ch.Q+cp_length+1:end);
    est_phase_diff = median(wrapToPi(angle(p_2) - angle(p_1))); %n*dw*T, with n = ch.Q+cp_length, and T = time_bin;
%     est_phase_diff = mean(angle(p_2.*conj(p_1)));
    CFO_rough_est = est_phase_diff/(2*pi*(time_bin)*(ch.Q+cp_length));
    r_CFO_corrected = add_CFO(r, -1*CFO_rough_est,time_bin);
    r = r_CFO_corrected;
else
    CFO_rough_est = 0;
end
%simple solution: taking the mean of all incoming signals
r_deMIMO = mean(r,1);
r_temp = reshape(r_deMIMO, ch.Q+cp_length, am_blocks_original);
r = r_temp(cp_length+1:end, :);
R = fft(r, ch.Q, 1);

if add_pilots_bool == 1 && pilot_percentage ~= 0
    R = R(:);
    R_pilot_compensated = zeros(size(R));
    for signal_row_index = 0:floor(length(R)/ch.Q)-1
        R_pilots = R(pilot_indices_row+ch.Q*signal_row_index);
        pilot_phase_errors = wrapToPi(angle(R_pilots)-angle(pilot_symbol));
        pilot_phase_errors = mean(pilot_phase_errors);
        R_pilot_compensated(ch.Q*signal_row_index+1:ch.Q*(signal_row_index+1)) = R(ch.Q*signal_row_index+1:ch.Q*(signal_row_index+1)).*exp(1j*-1*pilot_phase_errors);
%         figure
%         hold on
%         plot(R(pilot_indices_row+ch.Q*signal_row_index), 'x')
%         plot(R_pilot_compensated(pilot_indices_row+ch.Q*signal_row_index), 'o')
%         plot(pilot_symbol, 'o')
%         hold off
%         CFO_est_mean = CFO_est_mean + CFO_est_fine;
    end
    I_est = R_pilot_compensated;
else
%     I_est = R./H_current';
    I_est = R;
    I_est = I_est(:);
end


bits_restored = QAM_demodulation(I_est',bitspersymbol);
bits_restored(am_bits_original/2+1:end) = ones(1,am_bits_original/2) - bits_restored(am_bits_original/2+1:end);
BER = 0;
for i = 1:am_bits_original
    if bits(i) ~= bits_restored(i)
        BER = BER + 1;
    end
end
BER = BER / am_bits_original; %high!
ToA_sq_err = (est_offset-random_index)^2;
phase_offset_sq_err = 0;
CFO_rough_sq_err = (CFO_rough_est-CFO)^2;

end

