cimport xfftn
import numpy as np
cimport numpy as np
from numbers import Number
from libc.stdlib cimport malloc, free

directions = {'FFTW_FORWARD': FFTW_FORWARD,
        'FFTW_BACKWARD': FFTW_BACKWARD,
        'R2C': -2,
        'C2R': 2,
        'FFTW_REDFT00': FFTW_REDFT00,
        'FFTW_REDFT10': FFTW_REDFT10,
        'FFTW_REDFT01': FFTW_REDFT01,
        'FFTW_REDFT11': FFTW_REDFT11,
        'FFTW_RODFT00': FFTW_RODFT00,
        'FFTW_RODFT10': FFTW_RODFT10,
        'FFTW_RODFT01': FFTW_RODFT01,
        'FFTW_RODFT11': FFTW_RODFT11}

flag_dict = {'FFTW_MEASURE': FFTW_MEASURE,
        'FFTW_EXHAUSTIVE': FFTW_EXHAUSTIVE,
        'FFTW_PATIENT': FFTW_PATIENT,
        'FFTW_ESTIMATE': FFTW_ESTIMATE,
        'FFTW_UNALIGNED': FFTW_UNALIGNED,
        'FFTW_DESTROY_INPUT': FFTW_DESTROY_INPUT,
        'FFTW_PRESERVE_INPUT': FFTW_PRESERVE_INPUT,
        'FFTW_WISDOM_ONLY': FFTW_WISDOM_ONLY}

cdef fftw_plan* _planxfftn(int      ndims,
                      int      sizesA[],
                      void     *arrayA,
                      int      sizesB[],
                      void     *arrayB,
                      int      naxes,
                      int      axes[],
                      int      kind,
                      unsigned flags):
    return <fftw_plan *>planxfftn(ndims, sizesA, <void *> arrayA,
                                  sizesB, <void *> arrayB, naxes, 
                                  axes, kind, flags)

cdef fftw_plan* pyplanxfftn(ndims, arrayA, arrayB, naxes, axes, kind, flags):
    cdef int *szA = <int *> malloc(ndims * sizeof(int))
    cdef int *szB = <int *> malloc(ndims * sizeof(int))
    cdef int *axs = <int *> malloc(naxes * sizeof(int))
    cdef int i
    cdef fftw_plan *plan 
    for i in range(ndims):
        szA[i] = arrayA.shape[i]
        szB[i] = arrayB.shape[i]
    for i in range(naxes):
        axs[i] = axes[i]

    cdef void *_in = <void *>np.PyArray_DATA(arrayA)
    cdef void *_out = <void *>np.PyArray_DATA(arrayB)          
    plan = _planxfftn(ndims, szA, _in, szB, _out, naxes, axs, kind, flags)
    free(szA)
    free(szB)
    free(axs)
    return plan

cdef class FFT:
    cdef void *_plan
    cdef np.ndarray _input_array
    cdef np.ndarray _output_array
    cdef double _M

    def __cinit__(self, input_array, output_array, axes=(-1,), 
                  int kind=FFTW_FORWARD, int threads=1,
                  flags=(FFTW_MEASURE,), int M=1):
        cdef int ndims = len(input_array.shape)
        cdef int naxes = len(axes)
        cdef unsigned myflags
        cdef unsigned opt, destroy_input

        fftw_plan_with_nthreads(threads)
        opt = FFTW_MEASURE
        destroy_input = FFTW_DESTROY_INPUT
        flags = [flags] if isinstance(flags, Number) else flags
        
        for f in flags:
            if f in (FFTW_ESTIMATE, FFTW_MEASURE, FFTW_PATIENT, FFTW_EXHAUSTIVE):
                opt = f
            elif f in (FFTW_PRESERVE_INPUT, FFTW_DESTROY_INPUT):
                destroy_input = f
            else:
                raise RuntimeError

        self._plan = NULL
        self._input_array = input_array 
        self._output_array = output_array
        self._M = 1./M
        self._plan = pyplanxfftn(ndims, input_array, output_array, naxes, axes,
                                 kind, opt | destroy_input)

    def __call__(self, input_array=None, output_array=None, **kw):
        if input_array is not None:
            self._input_array[...] = input_array
        fftw_execute(<fftw_plan *>self._plan)
        if kw.get('normalize_idft', False):
            self._output_array *= self._M
        if output_array is not None:
            output_array[...] = self._output_array
            return output_array
        return self._output_array

    def __dealloc__(self):
        self.destroy()

    def destroy(self):
        fftw_destroy_plan(<fftw_plan *>self._plan)

    @property
    def input_array(self):
        return self._input_array

    @property
    def output_array(self):
        return self._output_array

def fftn(input_array, output_array, axes=(-1,), 
         int threads=1, flags=(FFTW_MEASURE,)):
    cdef int kind = FFTW_FORWARD
    assert input_array.dtype.char in 'fdgFDG'
    return FFT(input_array, output_array, axes, kind, threads, flags, 1)

def ifftn(input_array, output_array, axes=(-1,), 
          int threads=1, flags=(FFTW_MEASURE,), s=None):
    cdef int kind = FFTW_BACKWARD
    cdef int M, axis
    assert input_array.dtype.char in 'FDG'
    s = input_array.shape
    M = 1
    for axis in axes:
        M *= s[axis]
    return FFT(input_array, output_array, axes, kind, threads, flags, M)

def rfftn(input_array, output_array, axes=(-1,),
          int threads=1, flags=(FFTW_MEASURE,)):
    cdef int kind = R2C
    assert input_array.dtype.char in 'fdg'
    return FFT(input_array, output_array, axes, kind, threads, flags, 1)

def irfftn(input_array, output_array, axes=(-1,), 
           int threads=1, flags=(FFTW_MEASURE,)):
    cdef int kind = C2R
    cdef int M, axis
    assert input_array.dtype.char in 'FDG'
    s = input_array.shape
    M = 1
    for axis in axes:
        M *= s[axis]
    return FFT(input_array, output_array, axes, kind, threads, flags, M)

def dct(input_array, output_array, axes=(-1,), type=2, 
        int threads=1, flags=(FFTW_MEASURE,)):
    cdef int kind
    assert input_array.dtype.char in 'fdg'
    if type == 1:
        kind = FFTW_REDFT00
    elif type == 2:
        kind = FFTW_REDFT10  # inverse is type 3
    elif type == 3:
        kind = FFTW_REDFT01  # inverse is type 2
    return FFT(input_array, output_array, axes, kind, threads, flags, 1)

def idct(input_array, output_array, axes=(-1,), type=2,
         int threads=1, flags=(FFTW_MEASURE,)):
    cdef int kind
    assert input_array.dtype.char in 'fdg'
    cdef int M, axis
    s = input_array.shape  
    M = 1
    if type == 1:
        kind = FFTW_REDFT00
        for axis in axes:
            M *= 2*(s[axis]-1)
    elif type == 2:
        kind = FFTW_REDFT01
        for axis in axes:
            M *= 2*s[axis]
    elif type == 3:
        kind = FFTW_REDFT10
        for axis in axes:
            M *= 2*s[axis]
    return FFT(input_array, output_array, axes, kind, threads, flags, M)

