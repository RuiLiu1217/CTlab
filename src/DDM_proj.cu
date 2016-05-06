/*
 * COPYRIGHT NOTICE
 * COPYRIGHT (c) 2015, Wake Forest and UMass Lowell
 * All rights reserved
 *
 * @file DDM_proj.cu
 * @brief The GPU based DD projection in conventional method
 *
 * @version 1.0
 * @author Rui Liu
 * @date May. 1, 2015
 *
 */


#include "cuda_runtime.h"
#include "DDM_proj.h"


#ifndef PI
#define PI 3.14159265358979323846264
#endif

template<typename T>
__device__ inline T intersectLength_device(const T& fixedmin, const T& fixedmax, const T& varimin, const T& varimax)
{
	const T left = (fixedmin > varimin) ? fixedmin : varimin;
	const T right = (fixedmax < varimax) ? fixedmax : varimax;
	return abs(right - left) * static_cast<double>(right > left);
}



template<typename T>
__global__ void DDM_ED_proj_ker(T* proj, const T* img, const T S2O, const T O2D,
	const T objSizeX, const T objSizeY, const T detSize, const T detCntIdx,
	const int XN, const int YN, const int DN, const int PN, const T dd, const T dx, const T dy,
	const T* angs)
{
	const int detIdx = threadIdx.x + blockIdx.x * blockDim.x;
	const int angIdx = threadIdx.y + blockIdx.y * blockDim.y;
	if (detIdx < DN && angIdx < PN)
	{
		T curang = angs[angIdx];
		T minP = cos(curang);
		T maxP = sin(curang);
		T cursourX = S2O * minP;
		T cursourY = S2O * maxP;
		T summ = 0;

		T curDetXLeft = -O2D * minP + (detIdx - detCntIdx - 0.5) * dd * maxP; //当前det左边X坐标
		T curDetYLeft = -O2D * maxP - (detIdx - detCntIdx - 0.5) * dd * minP; //当前det左边Y坐标
		T curDetXRight = -O2D * minP + (detIdx - detCntIdx + 0.5) * dd * maxP; //当前det右边X坐标
		T curDetYRight = -O2D * maxP - (detIdx - detCntIdx + 0.5) * dd * minP; //当前det右边Y坐标

		T dirX = -O2D * minP + (detIdx - detCntIdx) * dd * maxP - cursourX;
		T dirY = -O2D * maxP - (detIdx - detCntIdx) * dd * minP - cursourY;
		T obj = hypot(dirX, dirY);
		dirX /= obj;
		dirY /= obj;
		T detPosLeft, detPosRight;
		T temp;
		int ii, jj;

		int minIdx, maxIdx;

		if ((curang > PI * 0.25 && curang <= PI * 0.75) || (curang >= PI * 1.25 && curang < PI * 1.75))
		{

			curang = abs(dirY); //当前光线和Y轴夹角余弦

			detPosLeft = (0 - cursourY) / (curDetYLeft - cursourY) * (curDetXLeft - cursourX) + cursourX; //det左边界X轴上的坐标;
			detPosRight = (0 - cursourY) / (curDetYRight - cursourY) * (curDetXRight - cursourX) + cursourX;//det右边界在x轴上的坐标;
			if (detPosLeft > detPosRight)
			{
				temp = detPosLeft;
				detPosLeft = detPosRight;
				detPosRight = temp;
			}

			for (jj = 0; jj < YN; jj++)
			{
				obj = (jj - YN / 2.0 + 0.5) * dy;
				minP = (obj - cursourY) / (curDetYLeft - cursourY) * (curDetXLeft - cursourX) + cursourX;
				maxP = (obj - cursourY) / (curDetYRight - cursourY) *  (curDetXRight - cursourX) + cursourX;
				if (minP > maxP)
				{
					temp = minP;
					minP = maxP;
					maxP = temp;

				}

				minIdx = floor(minP / dx + XN / 2.0);
				maxIdx = ceil(maxP / dx + XN / 2.0);

				if (maxIdx <= 0)
				{
					continue;
				}
				else if (minIdx > XN)
				{
					continue;
				}

				if (minIdx < 0)
				{
					minIdx = 0;
				}
				if (maxIdx > XN)
				{
					maxIdx = XN;
				}
				minP = (-cursourY) / (obj - cursourY) * ((minIdx - XN / 2.0) * dx - cursourX) + cursourX;
				for (ii = minIdx; ii < maxIdx; ++ii)
				{

					maxP = (-cursourY) / (obj - cursourY) * ((ii + 1 - XN / 2.0) * dx - cursourX) + cursourX;
					summ += img[jj * XN + ii] * intersectLength_device<double>(detPosLeft, detPosRight, minP, maxP);
					minP = maxP;
				}
			}
			proj[angIdx * DN + detIdx] = summ / (curang * (detPosRight - detPosLeft)) * dy;
			return;
		}
		else
		{

			curang = abs(dirX); //与Case1区别;
			detPosLeft = cursourX / (cursourX - curDetXLeft) * (curDetYLeft - cursourY) + cursourY; //det左边界X轴上的坐标;
			detPosRight = cursourX / (cursourX - curDetXRight) * (curDetYRight - cursourY) + cursourY;//det右边界在x轴上的坐标;

			if (detPosLeft > detPosRight)
			{
				temp = detPosLeft;
				detPosLeft = detPosRight;
				detPosRight = temp;
			}

			for (ii = 0; ii < XN; ++ii)
			{

				obj = (ii - YN / 2.0 + 0.5) * dy;
				minP = (obj - cursourX) / (curDetXLeft - cursourX) * (curDetYLeft - cursourY) + cursourY;
				maxP = (obj - cursourX) / (curDetXRight - cursourX) *  (curDetYRight - cursourY) + cursourY;
				if (minP > maxP)
				{
					temp = minP;
					minP = maxP;
					maxP = temp;
				}

				minIdx = floor(minP / dy + YN / 2.0);
				maxIdx = ceil(maxP / dy + YN / 2.0);

				if (maxIdx <= 0)
				{
					continue;
				}
				else if (minIdx > XN)
				{
					continue;
				}

				if (minIdx < 0)
				{
					minIdx = 0;
				}
				if (maxIdx > YN)
				{
					maxIdx = YN;
				}


				minP = (-cursourX) / (obj - cursourX) * ((minIdx - YN / 2.0) * dy - cursourY) + cursourY;
				for (jj = minIdx; jj < maxIdx; ++jj)
				{
					maxP = (-cursourX) / (obj - cursourX) * ((jj + 1 - YN / 2.0) * dy - cursourY) + cursourY;
					summ += img[jj * XN + ii] * intersectLength_device<double>(detPosLeft, detPosRight, minP, maxP);
					minP = maxP;
				}
			}

			proj[angIdx * DN + detIdx] = summ / (curang * (detPosRight - detPosLeft)) * dx;
		}

	}
}


template<typename T>
void DDM_ED_proj_GPU_template(T* proj, const T* img,
	const T S2O, const T O2D, const T objSizeX, const T objSizeY,
	const T detSize, const T detCntIdx,
	const int XN, const int YN, const int DN, const int PN, const T dd, const T dx, const T dy,
	const T* angs, const dim3 blk, const dim3 gid)
{
	DDM_ED_proj_ker<T> << <gid, blk >> >(proj, img, S2O, O2D, objSizeX, objSizeY,
		detSize, detCntIdx, XN, YN, DN, PN, dd, dx, dy, angs);

}





void DDM_ED_proj_GPU(double* proj, const double* img,
	const double S2O, const double O2D, const double objSizeX, const double objSizeY,
	const double detSize, const double detCntIdx,
	const int XN, const int YN, const int DN, const int PN, const double dd, const double dx, const double dy,
	const double* angs, const dim3 blk, const dim3 gid)
{
	DDM_ED_proj_GPU_template<double>(proj, img, S2O, O2D, objSizeX, objSizeY,
		detSize, detCntIdx, XN, YN, DN, PN, dd, dx, dy, angs, blk, gid);
}


void DDM_ED_proj_GPU(float* proj, const float* img,
	const float S2O, const float O2D, const float objSizeX, const float objSizeY,
	const float detSize, const float detCntIdx,
	const int XN, const int YN, const int DN, const int PN, const float dd, const float dx, const float dy,
	const float* angs, const dim3 blk, const dim3 gid)
{
	DDM_ED_proj_GPU_template<float>(proj, img, S2O, O2D, objSizeX, objSizeY,
		detSize, detCntIdx, XN, YN, DN, PN, dd, dx, dy, angs, blk, gid);
}

template<typename T>
__global__ void DDM_ED_bproj_ker(const T* proj, T* img,
	const T S2O, const T O2D, const T objSizeX, const T objSizeY,
	const T detSize,
	const T detCntIdx, const int XN, const int YN, const int DN, const int PN,
	const T dd, const T dx, const T dy, const T hfXN, const T hfYN,
	const T S2D,
	const T* angs)
{
	const int ii = threadIdx.x + blockIdx.x * blockDim.x;
	const int jj = threadIdx.y + blockIdx.y * blockDim.y;
	if (ii < XN && jj < YN)
	{
		T summ = 0;
		for (int angIdx = 0; angIdx < PN; angIdx++)
		{
			T curang = angs[angIdx];
			T cosT = cos(curang);
			T sinT = sin(curang);
			T lefPx(0);
			T lefPy(0);
			T rghPx(0);
			T rghPy(0);
			T temp(0);
			if ((curang > PI * 0.25 && curang <= PI * 0.75) || (curang >= PI * 1.25 && curang < PI * 1.75))
			{
				lefPx = (ii - hfXN) * dx;
				lefPy = (jj - hfYN + 0.5) * dy;
				rghPx = (ii - hfXN + 1.0) * dx;
				rghPy = (jj - hfYN + 0.5) * dy;
			}
			else
			{
				lefPx = (ii - hfXN + 0.5) * dx;
				lefPy = (jj - hfYN + 1.0) * dy;
				rghPx = (ii - hfXN + 0.5) * dx;
				rghPy = (jj - hfYN) * dy;
			}

			T initObjX1 = lefPx * cosT + lefPy * sinT;
			T initObjY1 = -lefPx * sinT + lefPy * cosT;
			T initObjX2 = rghPx * cosT + rghPy * sinT;
			T initObjY2 = -rghPx * sinT + rghPy * cosT;

			T objYdetPosMin = initObjY1 * S2D / (S2O - initObjX1);
			T objYdetPosMax = initObjY2 * S2D / (S2O - initObjX2);

			if (objYdetPosMax < objYdetPosMin)
			{
				temp = objYdetPosMax;
				objYdetPosMax = objYdetPosMin;
				objYdetPosMin = temp;

			}
			int minDetIdx = floor(objYdetPosMax / (-dd) + detCntIdx);
			int maxDetIdx = ceil(objYdetPosMin / (-dd) + detCntIdx);

			if (minDetIdx > DN)
			{
				continue;
			}
			if (maxDetIdx < 0)
			{
				continue;
			}

			T objYaxisPosMin = initObjX1 * initObjY1 / (S2O - initObjX1) + initObjY1; //pixel端点在Y轴上的投影;
			T objYaxisPosMax = initObjX2 * initObjY2 / (S2O - initObjX2) + initObjY2;
			if (objYaxisPosMax < objYaxisPosMin)
			{
				temp = objYaxisPosMax;
				objYaxisPosMax = objYaxisPosMin;
				objYaxisPosMin = temp;

			}
			T objYaxisLength = abs(objYaxisPosMax - objYaxisPosMin);

			if (minDetIdx < 0)
			{
				minDetIdx = 0;
			}
			if (maxDetIdx >= DN)
			{
				maxDetIdx = DN;
			}

			for (int detIdx = minDetIdx; detIdx < maxDetIdx; ++detIdx)
			{
				T maxDetPos = (-(detIdx - detCntIdx) * dd) * S2O / S2D;
				T minDetPos = (-(detIdx + 1.0 - detCntIdx) * dd) * S2O / S2D;
				if (maxDetPos < minDetPos)
				{
					temp = minDetPos;
					minDetPos = maxDetPos;
					maxDetPos = temp;

				}
				T s = (-(detIdx + 0.5 - detCntIdx) * dd) * S2O / S2D;

				T ll = sqrt(S2O * S2O + s * s);

				T cosAng = abs(S2O / ll);
				summ += proj[angIdx * DN + detIdx] * intersectLength_device<T>(objYaxisPosMin, objYaxisPosMax, minDetPos, maxDetPos) / (objYaxisLength * cosAng);

			}

			if ((curang > PI * 0.25 && curang <= PI * 0.75) || (curang >= PI * 1.25 && curang < PI * 1.75))
			{
				summ *= dy;
			}
			else
			{
				summ *= dx;
			}

		}
		img[jj * XN + ii] = summ;
	}
}


template<typename T>
void DDM_ED_bproj_GPU_template(const T* proj, T* img,
	const T S2O, const T O2D, const T objSizeX, const T objSizeY,
	const T detSize,
	const T detCntIdx, const int XN, const int YN, const int DN, const int PN,
	const T dd, const T dx, const T dy, const T hfXN, const T hfYN,
	const T S2D,
	const T* angs, const dim3 blk, const dim3 gid)
{
	DDM_ED_bproj_ker<T> << <gid, blk >> >(proj, img, S2O, O2D, objSizeX, objSizeY,
		detSize, detCntIdx, XN, YN, DN, PN, dd, dx, dy, hfXN, hfYN, S2D, angs);
}


void DDM_ED_bproj_GPU(const double* proj, double* img,
	const double S2O, const double O2D, const double objSizeX, const double objSizeY,
	const double detSize, const double detCntIdx, const int XN, const int YN, const int DN, const int PN,
	const double dd, const double dx, const double dy, const double hfXN, const double hfYN,
	const double S2D,
	const double* angs, const dim3 blk, const dim3 gid)
{
	DDM_ED_bproj_GPU_template<double>(proj, img, S2O, O2D, objSizeX, objSizeY,
		detSize, detCntIdx, XN, YN, DN, PN,
		dd, dx, dy, hfXN, hfYN, S2D, angs, blk, gid);
}


void DDM_ED_bproj_GPU(const float* proj, float* img,
	const float S2O, const float O2D, const float objSizeX, const float objSizeY,
	const float detSize, const float detCntIdx, const int XN, const int YN, const int DN, const int PN,
	const float dd, const float dx, const float dy, const float hfXN, const float hfYN,
	const float S2D,
	const float* angs, const dim3 blk, const dim3 gid)
{
	DDM_ED_bproj_GPU_template<float>(proj, img, S2O, O2D, objSizeX, objSizeY,
		detSize, detCntIdx, XN, YN, DN, PN,
		dd, dx, dy, hfXN, hfYN, S2D, angs, blk, gid);
}














template<typename T>
__global__ void DDM3D_ED_proj_GPU_template(T* proj, const T* vol,
	const T S2O, const T O2D,
	const T objSizeX, const T objSizeY, const T objSizeZ,
	const T detSizeU, const T detSizeV,
	const T detCntIdxU, const T detCntIdxV,
	const int XN, const int YN, const int ZN, const int DNU, const int DNV, const int PN,
	const T ddu, const T ddv, const T dx, const T dy, const T dz,
	const T* angs)
{
	const int detIdU = threadIdx.x + blockIdx.x * blockDim.x;
	const int detIdV = threadIdx.y + blockIdx.y * blockDim.y;
	const int angIdx = threadIdx.z + blockIdx.z * blockDim.z;
	if (detIdU < DNU && detIdV < DNV && angIdx < PN)
	{
		T curang = angs[angIdx];
		T cosT = cos(curang);
		T sinT = sin(curang);

		T cursourx = S2O * cosT;
		T cursoury = S2O * sinT;
		T cursourz = 0;
		T temp;
		T summ = 0;
		T initDetX = -O2D;


		T initDetY = (detIdU - detCntIdxU) * ddu;
		T initDetZ = (detIdV - detCntIdxV) * ddv;

		T initDetLY = (detIdU - detCntIdxU - 0.5) * ddu;
		//initDetLZ = (detIdV - detCntIdxV) * ddv;

		T initDetRY = (detIdU - detCntIdxU + 0.5) * ddu;
		//initDetRZ = (detIdV - detCntIdxV) * ddv;

		T initDetDY = (detIdU - detCntIdxU) * ddu;
		T initDetDZ = (detIdV - detCntIdxV - 0.5) * ddv;

		T initDetUY = (detIdU - detCntIdxU) * ddu;
		T initDetUZ = (detIdV - detCntIdxV + 0.5) * ddv;

		T curDetLX = initDetX * cosT - initDetLY * sinT;
		T curDetLY = initDetX * sinT + initDetLY * cosT;
		//curDetLZ = initDetLZ;

		T curDetRX = initDetX * cosT - initDetRY * sinT;
		T curDetRY = initDetX * sinT + initDetRY * cosT;
		//curDetRZ = initDetRZ;

		T curDetDX = initDetX * cosT - initDetDY * sinT;
		T curDetDY = initDetX * sinT + initDetDY * cosT;
		T curDetDZ = initDetDZ;

		T curDetUX = initDetX * cosT - initDetUY * sinT;
		T curDetUY = initDetX * sinT + initDetUY * cosT;
		T curDetUZ = initDetUZ;

		T curDetX = initDetX * cosT - initDetY * sinT;
		T curDetY = initDetX * sinT + initDetY * cosT;
		//curDetZ = initDetZ;

		T dirX = curDetX - cursourx;
		T dirY = curDetY - cursoury;
		//dirZ = curDetZ - cursourz;

		if ((curang > PI * 0.25 && curang <= PI * 0.75) || (curang >= PI * 1.25 && curang < PI * 1.75))
		{




			T cosAlpha = abs(dirY / sqrt(dirY * dirY + dirX * dirX));
			//cosGamma = abs(dirY / sqrt(dirY * dirY + dirZ * dirZ));
			T cosGamma = abs(sqrt((S2O + O2D)*(S2O + O2D) - initDetZ*initDetZ) / (S2O + O2D));

			T detPosLX = -cursoury * (curDetLX - cursourx) / (curDetLY - cursoury) + cursourx; //左边点在XOZ平面上的投影;
			T detPosRX = -cursoury * (curDetRX - cursourx) / (curDetRY - cursoury) + cursourx;
			T detPosDZ = -cursoury * (curDetDZ - cursourz) / (curDetDY - cursoury) + cursourz;
			T detPosUZ = -cursoury * (curDetUZ - cursourz) / (curDetUY - cursoury) + cursourz;

			T detprojLength = abs(detPosLX - detPosRX);
			T detprojHeight = abs(detPosUZ - detPosDZ);

			//假设左边的小;
			if (detPosLX > detPosRX)
			{
				temp = detPosLX;
				detPosLX = detPosRX;
				detPosRX = temp;
				//std::swap(detPosLX, detPosRX);
			}
			//假设下边的小;
			if (detPosDZ > detPosUZ)
			{
				temp = detPosDZ;
				detPosDZ = detPosUZ;
				detPosUZ = temp;
				//std::swap(detPosDZ, detPosUZ);
			}

			for (size_t jj = 0; jj < YN; jj++)
			{
				T objY = (jj - YN / 2.0 + 0.5) * dy;
				T temp = (objY - cursoury) / (curDetLY - cursoury);

				T minX = temp * (curDetLX - cursourx) + cursourx;
				T maxX = temp * (curDetRX - cursourx) + cursourx;
				T minZ = temp * (curDetDZ - cursourz) + cursourz;
				T maxZ = temp * (curDetUZ - cursourz) + cursourz;
				if (minX > maxX)
				{
					temp = minX;
					minX = maxX;
					maxX = temp;
					//std::swap(minX, maxX);
				}
				if (minZ > maxZ)
				{
					temp = minZ;
					minZ = maxZ;
					maxZ = temp;

					//std::swap(minZ, maxZ);
				}
				int minXIdx = floor(minX / dx + XN / 2.0) - 2;
				int maxXIdx = ceil(maxX / dx + XN / 2.0) + 2;
				int minZIdx = floor(minZ / dz + ZN / 2.0) - 2;
				int maxZIdx = ceil(maxZ / dz + ZN / 2.0) + 2;
				if (maxXIdx < 0){ continue; }
				if (minXIdx > XN){ continue; }
				if (maxZIdx < 0){ continue; }
				if (minZIdx > ZN){ continue; }
				if (minXIdx < 0){ minXIdx = 0; }
				if (maxXIdx > XN){ maxXIdx = XN; }
				if (minZIdx < 0){ minZIdx = 0; }
				if (maxZIdx > ZN){ maxZIdx = ZN; }


				for (size_t ii = minXIdx; ii < maxXIdx; ii++)
				{
					T curminx = (cursourx - (ii - XN / 2.0) * dx) * cursoury / (objY - cursoury) + cursourx;
					T curmaxx = (cursourx - ((ii + 1) - XN / 2.0) * dx) * cursoury / (objY - cursoury) + cursourx;
					T intersectL = intersectLength_device<double>(detPosLX, detPosRX, curminx, curmaxx);
					if (intersectL > 0)
					{
						for (size_t kk = minZIdx; kk < maxZIdx; kk++)
						{

							T curminz = (cursourz - (kk - ZN / 2.0) * dz) * cursoury / (objY - cursoury) + cursourz;
							T curmaxz = (cursourz - ((kk + 1) - ZN / 2.0) * dz) * cursoury / (objY - cursoury) + cursourz;

							T intersectH = intersectLength_device<double>(detPosDZ, detPosUZ, curminz, curmaxz);
							if (intersectH > 0)
							{
								summ += vol[(kk * YN + jj) * XN + ii] * (intersectL * intersectH) / (detprojLength * detprojHeight * cosAlpha * cosGamma) * dx;
							}
						}
					}
					else
					{
						continue;
					}

				}

			}
			proj[(angIdx * DNV + detIdV) * DNU + detIdU] = summ;
		}
		else
		{
			T cosAlpha = abs(dirX / sqrt(dirY * dirY + dirX * dirX));
			//cosGamma = abs(dirY / sqrt(dirY * dirY + dirZ * dirZ));
			T cosGamma = abs(sqrt((S2O + O2D)*(S2O + O2D) - initDetZ*initDetZ) / (S2O + O2D));

			T detPosLY = -cursourx * (curDetLY - cursoury) / (curDetLX - cursourx) + cursoury; //左边点在XOZ平面上的投影;
			T detPosRY = -cursourx * (curDetRY - cursoury) / (curDetRX - cursourx) + cursoury;
			T detPosDZ = -cursourx * (curDetDZ - cursourz) / (curDetDX - cursourx) + cursourz;
			T detPosUZ = -cursourx * (curDetUZ - cursourz) / (curDetUX - cursourx) + cursourz;

			T detprojLength = abs(detPosLY - detPosRY);
			T detprojHeight = abs(detPosUZ - detPosDZ);

			//假设左边的小;
			if (detPosLY > detPosRY)
			{
				temp = detPosLY;
				detPosLY = detPosRY;
				detPosRY = temp;
				//std::swap(detPosLY, detPosRY);
			}
			//假设下边的小;
			if (detPosDZ > detPosUZ)
			{
				temp = detPosDZ;
				detPosDZ = detPosUZ;
				detPosUZ = temp;
				//std::swap(detPosDZ, detPosUZ);
			}

			for (size_t ii = 0; ii < XN; ii++)
			{
				T objX = (ii - XN / 2.0 + 0.5) * dx;
				T temp = (objX - cursourx) / (curDetLX - cursourx);

				T minY = temp * (curDetLY - cursoury) + cursoury;
				T maxY = temp * (curDetRY - cursoury) + cursoury;
				T minZ = temp * (curDetDZ - cursourz) + cursourz;
				T maxZ = temp * (curDetUZ - cursourz) + cursourz;
				if (minY > maxY)
				{
					temp = minY;
					minY = maxY;
					maxY = temp;
					//std::swap(minY, maxY);
				}
				if (minZ > maxZ)
				{
					temp = minZ;
					minZ = maxZ;
					maxZ = temp;
					//std::swap(minZ, maxZ);
				}
				int minYIdx = floor(minY / dy + YN / 2.0) - 2;
				int maxYIdx = ceil(maxY / dy + YN / 2.0) + 2;
				int minZIdx = floor(minZ / dz + ZN / 2.0) - 2;
				int maxZIdx = ceil(maxZ / dz + ZN / 2.0) + 2;
				if (maxYIdx < 0){ continue; }
				if (minYIdx > XN){ continue; }
				if (maxZIdx < 0){ continue; }
				if (minZIdx > ZN){ continue; }
				if (minYIdx < 0){ minYIdx = 0; }
				if (maxYIdx > XN){ maxYIdx = YN; }
				if (minZIdx < 0){ minZIdx = 0; }
				if (maxZIdx > ZN){ maxZIdx = ZN; }


				for (size_t jj = minYIdx; jj < maxYIdx; jj++)
				{
					T curminy = (cursoury - (jj - YN / 2.0) * dy) * cursourx / (objX - cursourx) + cursoury;
					T curmaxy = (cursoury - ((jj + 1) - YN / 2.0) * dy) * cursourx / (objX - cursourx) + cursoury;
					T intersectL = intersectLength_device<double>(detPosLY, detPosRY, curminy, curmaxy);
					if (intersectL > 0)
					{
						for (size_t kk = minZIdx; kk < maxZIdx; kk++)
						{

							T curminz = (cursourz - (kk - ZN / 2.0) * dz) * cursourx / (objX - cursourx) + cursourz;
							T curmaxz = (cursourz - ((kk + 1) - ZN / 2.0) * dz) * cursourx / (objX - cursourx) + cursourz;

							T intersectH = intersectLength_device<double>(detPosDZ, detPosUZ, curminz, curmaxz);
							if (intersectH > 0)
							{
								summ += vol[(kk * YN + jj) * XN + ii] * (intersectL * intersectH) / (detprojLength * detprojHeight * cosAlpha * cosGamma) * dx;
							}
						}
					}
					else
					{
						continue;
					}

				}

			}
			proj[(angIdx * DNV + detIdV) * DNU + detIdU] = summ;
		}
	}
}
















void DDM3D_ED_proj_GPU(double* proj, const double* vol,
	const double S2O, const double O2D,
	const double objSizeX, const double objSizeY, const double objSizeZ,
	const double detSizeU, const double detSizeV,
	const double detCntIdxU, const double detCntIdxV,
	const int XN, const int YN, const int ZN, const int DNU, const int DNV, const int PN,
	const double ddu, const double ddv, const double dx, const double dy, const double dz,
	const double* angs, const dim3 blk, const dim3 gid)
{
	DDM3D_ED_proj_GPU_template<double> << <gid, blk >> >(proj, vol, S2O, O2D,
		objSizeX, objSizeY, objSizeZ, detSizeU, detSizeV,
		detCntIdxU, detCntIdxV, XN, YN, ZN, DNU, DNV, PN,
		ddu, ddv, dx, dy, dz, angs);
}

void DDM3D_ED_proj_GPU(float* proj, const float* vol,
	const float S2O, const float O2D,
	const float objSizeX, const float objSizeY, const float objSizeZ,
	const float detSizeU, const float detSizeV,
	const float detCntIdxU, const float detCntIdxV,
	const int XN, const int YN, const int ZN, const int DNU, const int DNV, const int PN,
	const float ddu, const float ddv, const float dx, const float dy, const float dz,
	const float* angs, const dim3 blk, const dim3 gid)
{
	DDM3D_ED_proj_GPU_template<float> << <gid, blk >> >(proj, vol, S2O, O2D,
		objSizeX, objSizeY, objSizeZ, detSizeU, detSizeV,
		detCntIdxU, detCntIdxV, XN, YN, ZN, DNU, DNV, PN,
		ddu, ddv, dx, dy, dz, angs);
}




template<typename T>
__global__ void DDM3D_ED_bproj_GPU_template(const T* proj, T* vol,
	const T S2O, const T O2D,
	const T objSizeX, const T objSizeY, const T objSizeZ,
	const T detSizeU, const T detSizeV,
	const T detCntIdU, const T detCntIdV,
	const int XN, const int YN, const int ZN, const int DNU, const int DNV, const int PN,
	const T ddu, const T ddv, const T dx, const T dy, const T dz,
	const T hfXN, const T hfYN, const T hfZN, const T S2D,
	const T* angs)
{
	const int ii = threadIdx.x + blockIdx.x * blockDim.x;
	const int jj = threadIdx.y + blockIdx.y * blockDim.y;
	const int kk = threadIdx.z + blockIdx.z * blockDim.z;
	if (ii < XN && jj < YN  && kk < ZN)
	{
		T summ = 0;
		T temp = 0;
		for (int angIdx = 0; angIdx != PN; ++angIdx)
		{
			T curang = angs[angIdx];
			T cosT = cos(curang);
			T sinT = sin(curang);
			T Px = (ii - hfXN + 0.5) * dx;
			T Py = (jj - hfYN + 0.5) * dy;
			T Pz = (kk - hfZN + 0.5) * dz;

			T lefPx(0);
			T lefPy(0);
			//T lefPz(0);

			T rghPx(0);
			T rghPy(0);
			//T rghPz(0);

			T uppPx(0);
			T uppPy(0);
			T uppPz(0);

			T dowPx(0);
			T dowPy(0);
			T dowPz(0);

			if ((curang > PI * 0.25 && curang <= PI * 0.75) || (curang >= PI * 1.25 && curang < PI * 1.75))
			{
				lefPx = Px - 0.5 * dx;
				lefPy = Py;
				//lefPz = Pz;

				rghPx = Px + 0.5 * dx;
				rghPy = Py;
				//rghPz = Pz;

				uppPx = Px;
				uppPy = Py;
				uppPz = Pz + 0.5 * dz;

				dowPx = Px;
				dowPy = Py;
				dowPz = Pz - 0.5 * dz;

			}
			else
			{
				lefPx = Px;
				lefPy = Py - 0.5 * dy;
				//lefPz = Pz;

				rghPx = Px;
				rghPy = Py + 0.5 * dy;
				//rghPz = Pz;

				uppPx = Px;
				uppPy = Py;
				uppPz = Pz + 0.5 * dz;

				dowPx = Px;
				dowPy = Py;
				dowPz = Pz - 0.5 * dz;
			}

			T initObjlefx = lefPx * cosT + lefPy * sinT;
			T initObjlefy = -lefPx * sinT + lefPy * cosT;
			//T initObjlefz = lefPz;

			T initObjrghx = rghPx * cosT + rghPy * sinT;
			T initObjrghy = -rghPx * sinT + rghPy * cosT;
			//T initObjrghz = rghPz;

			T initObjuppx = uppPx * cosT + uppPy * sinT;
			//T initObjuppy = -uppPx * sinT + uppPy * cosT;
			T initObjuppz = uppPz;

			T initObjdowx = dowPx* cosT + dowPy * sinT;
			//T initObjdowy = -dowPx * sinT + dowPy * cosT;
			T initObjdowz = dowPz;

			T objYdetPosUMin = initObjlefy * S2D / (S2O - initObjlefx);
			T objYdetPosUMax = initObjrghy * S2D / (S2O - initObjrghx);
			T objYdetPosVMin = initObjdowz * S2D / (S2O - initObjdowx);
			T objYdetPosVMax = initObjuppz * S2D / (S2O - initObjuppx);

			if (objYdetPosUMin > objYdetPosUMax)
			{
				temp = objYdetPosUMin;
				objYdetPosUMin = objYdetPosUMax;
				objYdetPosUMax = temp;
				//std::swap(objYdetPosUMin, objYdetPosUMax);
			}
			if (objYdetPosVMin > objYdetPosVMax)
			{
				temp = objYdetPosVMin;
				objYdetPosVMin = objYdetPosVMax;
				objYdetPosVMax = temp;

			}
			int minDetUIdx = floor(objYdetPosUMin / ddu + detCntIdU) - 1;
			int maxDetUIdx = ceil(objYdetPosUMax / ddu + detCntIdU) + 1;
			int minDetVIdx = floor(objYdetPosVMin / ddv + detCntIdV) - 1;
			int maxDetVIdx = ceil(objYdetPosVMax / ddv + detCntIdV) + 1;

			if (minDetUIdx > DNU)
			{
				continue;
			}
			if (maxDetUIdx < 0)
			{
				continue;
			}
			if (minDetVIdx > DNV)
			{
				continue;
			}
			if (maxDetVIdx < 0)
			{
				continue;
			}

			T objYOZLength = objYdetPosUMax - objYdetPosUMin;
			T objYOZHeight = objYdetPosVMax - objYdetPosVMin;


			if (minDetUIdx < 0)
			{
				minDetUIdx = 0;
			}
			if (maxDetUIdx > DNU)
			{
				maxDetUIdx = DNU;
			}
			if (minDetVIdx < 0)
			{
				minDetVIdx = 0;
			}
			if (maxDetVIdx > DNV)
			{
				maxDetVIdx = DNV;
			}


			for (int detIdU = minDetUIdx; detIdU < maxDetUIdx; ++detIdU)
			{
				T minDetUPos = (detIdU - detCntIdU - 0.5) * ddu;// *S2O / S2D;
				T maxDetUPos = (detIdU - detCntIdU + 0.5) * ddu;// *S2O / S2D;

				T ll = intersectLength_device<T>(objYdetPosUMin, objYdetPosUMax, minDetUPos, maxDetUPos);
				if (ll > 0)
				{
					for (int detIdV = minDetVIdx; detIdV < maxDetVIdx; ++detIdV)
					{
						T minDetVPos = (detIdV - detCntIdV - 0.5) * ddv;// *S2O / S2D;
						T maxDetVPos = (detIdV - detCntIdV + 0.5) * ddv;// *S2O / S2D;

						T DU = (detIdU - detCntIdU) * ddu;
						T DV = (detIdV - detCntIdV) * ddv;
						T cosAlphacosGamma = S2D / sqrt(DU*DU + DV*DV + S2D*S2D);
						T mm = intersectLength_device<T>(objYdetPosVMin, objYdetPosVMax, minDetVPos, maxDetVPos);
						if (mm > 0)
						{
							summ += (proj[(angIdx * DNV + detIdV) * DNU + detIdU] * ll * mm / (objYOZLength * objYOZHeight * cosAlphacosGamma) * dx);
						}
						else
						{
							summ += 0;
						}

					}
				}

			}


		}
		vol[(kk * YN + jj) * XN + ii] = summ;
	}
}

void DDM3D_ED_bproj_GPU(const double* proj, double* vol,
	const double S2O, const double O2D,
	const double objSizeX, const double objSizeY, const double objSizeZ,
	const double detSizeU, const double detSizeV,
	const double detCntIdU, const double detCntIdV,
	const int XN, const int YN, const int ZN, const int DNU, const int DNV, const int PN,
	const double ddu, const double ddv, const double dx, const double dy, const double dz,
	const double hfXN, const double hfYN, const double hfZN, const double S2D,
	const double* angs, const dim3 blk, const dim3 gid)
{
	DDM3D_ED_bproj_GPU_template<double> << <gid, blk >> >(proj, vol,
		S2O, O2D, objSizeX, objSizeY, objSizeZ, detSizeU, detSizeV,
		detCntIdU, detCntIdV, XN, YN, ZN, DNU, DNV, PN,
		ddu, ddv, dx, dy, dz, hfXN, hfYN, hfZN, S2D, angs);
}

void DDM3D_ED_bproj_GPU(const float* proj, float* vol,
	const float S2O, const float O2D,
	const float objSizeX, const float objSizeY, const float objSizeZ,
	const float detSizeU, const float detSizeV,
	const float detCntIdU, const float detCntIdV,
	const int XN, const int YN, const int ZN, const int DNU, const int DNV, const int PN,
	const float ddu, const float ddv, const float dx, const float dy, const float dz,
	const float hfXN, const float hfYN, const float hfZN, const float S2D,
	const float* angs, const dim3 blk, const dim3 gid)
{
	DDM3D_ED_bproj_GPU_template<float> << <gid, blk >> >(proj, vol,
		S2O, O2D, objSizeX, objSizeY, objSizeZ, detSizeU, detSizeV,
		detCntIdU, detCntIdV, XN, YN, ZN, DNU, DNV, PN,
		ddu, ddv, dx, dy, dz, hfXN, hfYN, hfZN, S2D, angs);
}

