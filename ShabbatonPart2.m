% A skeleton BER script for a wireless link simulation
clear all;close all;clc
% For the final version of this project, you must use these 3
% parameter. You will likely want to set numIter to 1 while you debug your
% link, and then increase it to get an average BER.
numIter = 100;  % The number of iterations of the simulation
nSym = 1000;    % The number of symbols per packet
SNR_Vec = 0:2:12;
SNR_Vec = 12;
lenSNR = length(SNR_Vec);
h = waitbar(0,'Starting waitbar...');

M = 32;          % The M-ary number, 2 corresponds to binary modulation
k = log2(M);    % number of bits per symbol

%chan = 1;          % No channel
chan = [1 .2 .4]; % Somewhat invertible channel impulse response, Moderate ISI
%chan = [0.227 0.460 0.688 0.460 0.227]';   % Not so invertible, severe ISI


% Time-varying Rayleigh multipath channel, try it if you dare. Or take
% wireless comms next semester.
% ts = 1/1000;
% chan = rayleighchan(ts,1);
% chan.pathDelays = [0 ts 2*ts];
% chan.AvgPathGaindB = [0 5 10];
% chan.StoreHistory = 1; % Uncomment if you want to be able to do plot(chan)
% 

% Create a vector to store the BER computed during each iteration
berVec = zeros(numIter, lenSNR);
berVec_uneq = zeros(numIter, lenSNR);
trainlen = 100;

% Run the simulation numIter amount of times
for i = 1:numIter
    
    bits = randi([0 1], 1, nSym*k/2);     % Generate random bits
    % New bits must be generated at every
    % iteration

    % If you increase the M-ary number, as you most likely will, you'll need to
    % convert the bits to integers. See the BIN2DE function
    % For binary, our MSG signal is simply the bits
    
    % Conv encode
    trellis = poly2trellis(7,{'1 + x^3 + x^4 + x^5 + x^6','1 + x + x^3 + x^4 + x^6'});
    code = convenc(bits, trellis, 0);
   
    msg = bi2de(reshape(code,k,length(code)/k).','left-msb')';
    
    % Reed Solomon encoding
    m = k;
    n = 2^m - 1;
    kRS = 5; % 5:15 RS code
    reshapedMsg = reshape(msg, nSym/kRS, kRS);
    msg = gf(reshapedMsg, m);
    code = rsenc(msg, n, kRS);
    code = double(code.x);
    msg = reshape(code, 1, n * nSym/kRS);
    
    for j = 1:lenSNR % one iteration of the simulation at each SNR Value

        tx = qammod(msg, M, 0, 'gray');  % BPSK modulate the signal
        % why am I QAMing my training bits?
        if isequal(chan,1)
            txChan = tx;
        elseif isa(chan,'channel.rayleigh')
            reset(chan) % Draw a different channel each iteration
            txChan = filter(chan,tx);
        else
            txChan = filter(chan,1,tx);  % Apply the channel.
        end
 
        txNoisy = awgn(txChan, SNR_Vec(j) + 10*log10(k), 'measured'); % Add AWGN
        
        % Equalize the signal
        forgetfactor = .999;
        eqobj = dfe(7, 2, rls(forgetfactor, .01));
        eqobj.SigConst = qammod(0:(M - 1), M);
        eqobj.ResetBeforeFiltering = 0;
        %eqobj = dfe(5, 5, rls(forgetfactor, .01), qammod(0:(M-1), M, 0, 'gray'));
        
        txeq = equalize(eqobj, txNoisy, tx(1:trainlen));
        
%         h = scatterplot(txNoisy,1,trainlen,'bx'); hold on;
%         scatterplot(txeq,1,trainlen,'g.',h);
%         scatterplot(eqobj.SigConst,1,0,'k*',h);
%         legend('Filtered signal','Equalized signal',...
%            'Ideal signal constellation');
%         hold off;
        
        % Demodulate
        rx = qamdemod(txeq, M, 0, 'gray'); 
        rx_uneq = qamdemod(txNoisy, M, 0, 'gray');
        
        % Reed Solomon decoding
        rxrshp = reshape(rx,nSym/kRS,n); 
        gfedrx = gf(rxrshp,m);
        decodedrx = rsdec(gfedrx,n,kRS);
        decodedrx = double(decodedrx.x);
        rx = reshape(decodedrx,1,nSym);

        % Again, if M was a larger number, I'd need to convert my symbols
        % back to bits here.
        rx = de2bi(rx,'left-msb'); % Map Symbols to Bits
        rx = reshape(rx.',numel(rx),1);
        rx_uneq = de2bi(rx_uneq,'left-msb'); % Map Symbols to Bits
        rx_uneq = reshape(rx_uneq.',numel(rx_uneq),1);
        
        % Conv decode - viterbi
        rx = vitdec(rx, trellis, 10, 'trunc', 'hard')';
        %rx_uneq = vitdec(rx_uneq, trellis, 10, 'trunc', 'hard')';

        rxMSG = rx(k*trainlen+1:end);
        %rxMSG_uneq = rx_uneq(k*trainlen+1:end);
       
        
        % Compute and store the BER for this iteration

        [zzz, berVec(i,j)] = biterr(bits(k*trainlen+1:end), rxMSG);  % We're interested in the BER, which is the 2nd output of BITERR
        %[zzz, berVec_uneq(i,j)] = biterr(bits(k*trainlen+1:end), rxMSG_uneq);  % We're interested in the BER, which is the 2nd output of BITERR
        
    end  % End SNR iteration
    
    waitbar(i/numIter,h,sprintf('%d%% done',100*i/numIter));
end      % End numIter iteration


% Compute and plot the mean BER
ber = mean(berVec,1)
ber_uneq = mean(berVec_uneq,1);

semilogy(SNR_Vec, ber)
hold on;
%semilogy(SNR_Vec, ber_uneq)

% Compute the theoretical BER for this scenario
% THIS IS ONLY VALID FOR BPSK!
% YOU NEED TO CHANGE THE CALL TO BERAWGN FOR DIFF MOD TYPES
% Also note - there is no theoretical BER when you have a multipath channel
if M == 2
    berTheory = berawgn(SNR_Vec,'psk',M,'nondiff');
else
    berTheory = berawgn(SNR_Vec, 'qam', M);
end
hold on
semilogy(SNR_Vec,berTheory,'r')
legend('equalized BER', 'theoretical BER')

close(h);

bitrate = (length(bits) - trainlen)/1000