!=====================================================================
!
!          S p e c f e m 3 D  G l o b e  V e r s i o n  5 . 1
!          --------------------------------------------------
!
!          Main authors: Dimitri Komatitsch and Jeroen Tromp
!                        Princeton University, USA
!             and CNRS / INRIA / University of Pau, France
! (c) Princeton University and CNRS / INRIA / University of Pau
!                            April 2011
!
! This program is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 2 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License along
! with this program; if not, write to the Free Software Foundation, Inc.,
! 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
!
!=====================================================================


  subroutine get_attenuation_model_3D(myrank, prname, one_minus_sum_beta, &
                                factor_common, scale_factor, tau_s, vnspec)

  implicit none

  include 'constants.h'

  integer myrank, vnspec
  character(len=150) prname
  real(kind=CUSTOM_REAL), dimension(NGLLX,NGLLY,NGLLZ,vnspec)       :: one_minus_sum_beta, scale_factor
  real(kind=CUSTOM_REAL), dimension(N_SLS,NGLLX,NGLLY,NGLLZ,vnspec) :: factor_common
  double precision, dimension(N_SLS)                          :: tau_s

  integer i,j,k,ispec

  double precision, dimension(N_SLS) :: tau_e, fc
  double precision  omsb, Q_mu, sf, T_c_source, scale_t

  ! All of the following reads use the output parameters as their temporary arrays
  ! use the filename to determine the actual contents of the read
  open(unit=27, file=prname(1:len_trim(prname))//'attenuation.bin', &
        status='old',action='read',form='unformatted')
  read(27) tau_s
  read(27) factor_common
  read(27) scale_factor
  read(27) T_c_source
  close(27)

  scale_t = ONE/dsqrt(PI*GRAV*RHOAV)

  factor_common(:,:,:,:,:) = factor_common(:,:,:,:,:) / scale_t ! This is really tau_e, not factor_common
  tau_s(:)                 = tau_s(:) / scale_t
  T_c_source               = 1000.0d0 / T_c_source
  T_c_source               = T_c_source / scale_t

  do ispec = 1, vnspec
     do k = 1, NGLLZ
        do j = 1, NGLLY
           do i = 1, NGLLX
              tau_e(:) = factor_common(:,i,j,k,ispec)
              Q_mu     = scale_factor(i,j,k,ispec)

              ! Determine the factor_common and one_minus_sum_beta from tau_s and tau_e
              call get_attenuation_property_values(tau_s, tau_e, fc, omsb)

              factor_common(:,i,j,k,ispec)    = fc(:)
              one_minus_sum_beta(i,j,k,ispec) = omsb

              ! Determine the "scale_factor" from tau_s, tau_e, central source frequency, and Q
              call get_attenuation_scale_factor(myrank, T_c_source, tau_e, tau_s, Q_mu, sf)
              scale_factor(i,j,k,ispec) = sf
           enddo
        enddo
     enddo
  enddo

  end subroutine get_attenuation_model_3D

!
!-------------------------------------------------------------------------------------------------
!
  subroutine get_attenuation_property_values(tau_s, tau_e, factor_common, one_minus_sum_beta)

  implicit none

  include 'constants.h'

  double precision, dimension(N_SLS) :: tau_s, tau_e, beta, factor_common
  double precision  one_minus_sum_beta

  double precision, dimension(N_SLS) :: tauinv
  integer i

  tauinv(:) = -1.0d0 / tau_s(:)

  beta(:) = 1.0d0 - tau_e(:) / tau_s(:)
  one_minus_sum_beta = 1.0d0

  do i = 1,N_SLS
     one_minus_sum_beta = one_minus_sum_beta - beta(i)
  enddo

!ZN beware, here the expression differs from the strain used in memory variable equation (6) in D. Komatitsch and J. Tromp 1999,
!ZN here Brian Savage uses the engineering strain which are epsilon = 1/2*(grad U + (grad U)^T),
!ZN where U is the displacement vector and grad the gradient operator, i.e. there is a 1/2 factor difference between the two.
!ZN Both expressions are fine, but we need to keep in mind that if we have put the 1/2 factor there we need to remove it
!ZN from the expression in which we use the strain here in the code.
!ZN This is why here Brian Savage multiplies beta(:) * tauinv(:) by 2.0 to compensate for the 1/2 factor used before
  factor_common(:) = 2.0d0 * beta(:) * tauinv(:)

  end subroutine get_attenuation_property_values

!
!-------------------------------------------------------------------------------------------------
!

  subroutine get_attenuation_scale_factor(myrank, T_c_source, tau_mu, tau_sigma, Q_mu, scale_factor)

  implicit none

  include 'constants.h'

  integer myrank
  double precision scale_factor, Q_mu, T_c_source
  double precision, dimension(N_SLS) :: tau_mu, tau_sigma

  double precision scale_t
  double precision f_c_source, w_c_source, f_0_prem
  double precision factor_scale_mu0, factor_scale_mu
  double precision a_val, b_val
  double precision big_omega
  integer i

  scale_t = ONE/dsqrt(PI*GRAV*RHOAV)

  !--- compute central angular frequency of source (non dimensionalized)
  f_c_source = ONE / T_c_source
  w_c_source = TWO_PI * f_c_source

  !--- non dimensionalize PREM reference of 1 second
  f_0_prem = ONE / ( ONE / scale_t)

!--- quantity by which to scale mu_0 to get mu
! this formula can be found for instance in
! Liu, H. P., Anderson, D. L. and Kanamori, H., Velocity dispersion due to
! anelasticity: implications for seismology and mantle composition,
! Geophys. J. R. Astron. Soc., vol. 47, pp. 41-58 (1976)
! and in Aki, K. and Richards, P. G., Quantitative seismology, theory and methods,
! W. H. Freeman, (1980), second edition, sections 5.5 and 5.5.2, eq. (5.81) p. 170
  factor_scale_mu0 = ONE + TWO * log(f_c_source / f_0_prem) / (PI * Q_mu)

  !--- compute a, b and Omega parameters, also compute one minus sum of betas
  a_val = ONE
  b_val = ZERO

  do i = 1,N_SLS
    a_val = a_val - w_c_source * w_c_source * tau_mu(i) * &
      (tau_mu(i) - tau_sigma(i)) / (1.d0 + w_c_source * w_c_source * tau_mu(i) * tau_mu(i))
    b_val = b_val + w_c_source * (tau_mu(i) - tau_sigma(i)) / &
      (1.d0 + w_c_source * w_c_source * tau_mu(i) * tau_mu(i))
  enddo

  big_omega = a_val*(sqrt(1.d0 + b_val*b_val/(a_val*a_val))-1.d0)

  !--- quantity by which to scale mu to get mu_relaxed
  factor_scale_mu = b_val * b_val / (TWO * big_omega)

  !--- total factor by which to scale mu0
  scale_factor = factor_scale_mu * factor_scale_mu0

  !--- check that the correction factor is close to one
  if(scale_factor < 0.8 .or. scale_factor > 1.2) then
     write(*,*)'scale factor: ', scale_factor
     call exit_MPI(myrank,'incorrect correction factor in attenuation model')
  endif

  end subroutine get_attenuation_scale_factor


!
!-------------------------------------------------------------------------------------------------
!


  subroutine get_attenuation_memory_values(tau_s, deltat, alphaval,betaval,gammaval)

  implicit none

  include 'constants.h'

  double precision, dimension(N_SLS) :: tau_s, alphaval, betaval,gammaval
  real(kind=CUSTOM_REAL) deltat

  double precision, dimension(N_SLS) :: tauinv

  tauinv(:) = - 1.0 / tau_s(:)

  alphaval(:)  = 1 + deltat*tauinv(:) + deltat**2*tauinv(:)**2 / 2. + &
                    deltat**3*tauinv(:)**3 / 6. + deltat**4*tauinv(:)**4 / 24.
  betaval(:)   = deltat / 2. + deltat**2*tauinv(:) / 3. &
                + deltat**3*tauinv(:)**2 / 8. + deltat**4*tauinv(:)**3 / 24.
  gammaval(:)  = deltat / 2. + deltat**2*tauinv(:) / 6. &
                + deltat**3*tauinv(:)**2 / 24.0

  end subroutine get_attenuation_memory_values

