#pragma once

template<typename T>
struct CPLX
{
	T re = 0;
	T im = 0;

	CPLX(T r = 0, T i = 0) : re(r), im(i) {};

	CPLX operator +(CPLX c) {
		CPLX temp;
		temp.re = this->re + c.re;
		temp.im = this->im + c.im;
		return(temp);
	}

	CPLX operator -(CPLX c) {
		CPLX temp;
		temp.re = this->re - c.re;
		temp.im = this->im - c.im;
		return(temp);
	}

	CPLX& operator+=(const CPLX& c) {
		this->re += c.re;
		this->im += c.im;
		return *this;
	}

	CPLX operator *(const CPLX& c) {
		CPLX<int> temp;
		temp.re = this->re * c.re - this->im * c.im;
		temp.im = this->re * c.im + this->im * c.re;
		CPLX t {static_cast<T>(temp.re / 8192), static_cast<T>(temp.im / 8192) };
		return t;
	}
};

