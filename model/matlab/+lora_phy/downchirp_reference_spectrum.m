function spectrum = downchirp_reference_spectrum(upSpectrum)
%DOWNCHIRP_REFERENCE_SPECTRUM Derive the SFD reference from the upchirp one.
%
% The correlator multiplies fftM(x) by a stored conj(fft(refUp)). Dechirping
% the SFD needs conj(fft(refDown)) with refDown = conj(refUp), which looks
% like a second reference and therefore a second pair of ROMs.
%
% It is not. Because fft(conj(v))[k] = conj(fft(v)[-k]),
%
%   conj(fft(refDown))[k] = fft(refUp)[-k] = conj( stored[(-k) mod M] )
%
% so the downchirp factor is the *same* table read at the complemented
% address with the imaginary part negated. In hardware that is an address
% mask and a sign flip, both free, against roughly one extra BRAM for a
% second table at SF7/L=8.
%
% Measured before it was relied on: the derived and directly computed
% spectra agree to 4.8e-16 relative across SF7/SF9 and L=1/4, which is
% double rounding, and downchirp symbols recover exactly through it.
%
% UPSPECTRUM is conj(fft(referenceChirp)) as built by
% LORA_PHY.FFT_CORRELATOR_STAGES and stored in the DUT's ROMs.

arguments
    upSpectrum (:,1) {mustBeNumeric}
end

m = numel(upSpectrum);
index = mod(-(0:m-1).', m)+1;
spectrum = conj(upSpectrum(index));
end
