Module Variables
  !
  !  VARIABLES
  !
  ! equil(9,273) : coefficients of the series expansion of the equilibrium constant
  ! molec(273) : name of the molecule as it appears in the file
  ! nombre(273) : name of the molecule
  ! elements(21) : name of the 21 atomic elements included
  ! abund(21) : abundance of the 21 atomic elements 
  ! pot_ion(21) : ionization potential of the 21 species included
  ! afinidad(21) : electronic affinity of the 21 species included
  ! estequio(i,j) : stequiometric coefficient of the species j into molecule i
  ! charge(273) : charge of the molecule
  ! composicion(i,j) : atoms which constitute molecule i (j=1..4)
  ! includ(273) : which molecules are included
  ! n_atoms_mol(273) : number of atoms in each molecule for its units transformation
  ! atomic_partition(i,j,k) : coefficient i of the atomic species k. The charge is indicated by j
  !                        (j = 0:neutral, 1:positive, 2:negative)
  ! equilibrium(i) : equilibrium constant at a given temperature for the whole set of molecules
  ! equilibrium_atomic(i,j) : equilibrium constant for the atomic species j for the positive (j=1)
  !                        ionization (A->A+ + e-) or the negative ionization (j=2) (A+e- ->A-)
  ! x_sol(21) : the abundance of every species during the iteration
  ! x0_sol(21) : the abundance of every species at the beggining of the iteration
  
  real(kind=8), SAVE :: equil(9,273)
  integer :: eqstate_switch=0 ! Choice for calculation of Pe and Pg
                            ! 0=Use NICOLE approach
                            ! 1=Use simple ANNs
                            ! 2=Use Wittmann's
  integer :: eqstate_switch_others=0 ! Choice for calculation of H,H+,H-,H2,H2+
                             ! 0=Use NICOLE approach, with
                             !     ANN trained with Andres code (273 molec)
                             ! 1=Use Andres code (2 molec)
                             ! 2=Use Andres code (273 molec)
                             ! 3=Use Wittmann's
  integer, SAVE  :: print_abund
  real :: eqstate_pe_consistency
  character(len=16), SAVE  :: molec(273), nombre_mol(273)
  character(len=2), SAVE :: elements(21)
  real(kind=8), SAVE :: abund_atom(21), pot_ion(21), afinidad(21)
  integer, SAVE :: which_index_element(21) = (/1,2,6,7,8,9,11,12,13,14,15,16,17,19,&
       20,22,24,25,26,28,29/)
  integer, SAVE :: estequio(273,21), charge(273), composicion(273,4), n_iters, includ(273), n_included
  integer, SAVE :: output_species
  real(kind=8), SAVE :: n_atoms_mol(273)
  real(kind=8), allocatable, SAVE :: which_included(:)
  real(kind=8), SAVE :: atomic_partition(7,3,21)
  real(kind=8), SAVE :: equilibrium(273), nh, temper, n_e, equilibrium_atomic(2,21)
  real(kind=8), parameter :: NA_ME = -4.89104734208d0, PK_CH = 1.3806503d-16
  real(kind=8), parameter :: Min_Pg=1e-3, Max_Pg=1e6, Min_Pe=1e-3, Max_Pe=1e5
  real(kind=8), SAVE :: x_sol(22), x0_sol(22), P_total, P_elec
  !  Data Elements/'H_','HE','C_','N_','O_','F_','NA','MG','AL','SI', &
  !       'P_','S_','CL','K_','CA','TI','CR','MN','FE','NI','CU'/
  Data Elements/'H ','HE','C ','N ','O ','F ','NA','MG','AL','SI', &
       'P ','S ','CL','K ','CA','TI','CR','MN','FE','NI','CU'/
  Data Afinidad/0.80,0.00,1.12,0.00,1.47,3.45,0.00,0.00,0.44,1.38,&
       0.75,2.07,3.61,0.00,0.08,0.00,0.00,0.00,0.00,0.00,0.00/
  
End Module Variables


!*******************************************************************
! Nonlinear system of equations solver
!*******************************************************************
module equations
  use variables
  implicit none
contains
  
  
  
  !-------------------------------------------------------------------
  ! Returns the value of the equations of the nonlinear set to be solved
  ! The equations are valid for obtaining Pg from Pe and T
  ! P(22) is the total pressure
  ! P(1:21) are the pressures of each element
  !-------------------------------------------------------------------
  subroutine funcv_Pg_from_T_Pe(x,n,fvec,gmat)
    integer :: n
    real(kind=8) :: x(n), fvec(n), gmat(n,n), components(4)
    integer :: i, j, k, l, m, ind, minim, ind2
    real(kind=8) :: P(n), salida, interna, P_e, minim_ioniz, dinterna(n)
    
    P = x
    
    fvec = 0.d0
    gmat = 0.d0
    
    ! We know that P_T = P(H)+P(He)+P(C)+...+Pe
    ! where P(i)=a(i)*P(H), with a(i) the abundance of element i with respect to H
    ! Therefore, P_T=K*P(H)+Pe, where K=sum(a(i)). Consequently, P(H) can be isolated and
    ! be P(H)=(P_T-Pe)/K
    ! Then, P(i) = a(i) * (P_T-Pe)/K
    x0_sol(1:21) = abund_atom * (P(22) - P_elec) / sum(abund_atom)
    
    do i = 1, 21
       salida = 0.d0
       
       ! If temperature is very high, do not take into account molecular formation
       if (temper < 1.d5) then
          do j = 1, n_included
             k = which_included(j)
             interna = 0.d0
             dinterna = 0.d0
             interna = 1.d0
             
             minim = 0
             minim_ioniz = 100.d0
             
             ! Product of the partial pressures of the components of molecule k
             do l = 1, 4
                ind = composicion(k,l)
                
                if (ind /= 0.d0) then                  
                   if (pot_ion(ind) < minim_ioniz) then
                      minim = ind
                      minim_ioniz = pot_ion(ind)
                   endif
                   
                   interna = interna*P(ind)**estequio(k,ind)
                   
                   ! Derivatives
                   do m = 1, 4
                      ind2 = composicion(k,m)
                      
                      if (ind2 /= 0.d0) then
                         
                         if (ind2 == ind) then
                            
                            ! Include the derivative of P(i) on df(i)/dP(i)
                            if (dinterna(ind) == 0.d0) then
                               dinterna(ind) = estequio(k,ind) * P(ind)**(estequio(k,ind)-1.d0)
                            else
                               dinterna(ind2) = dinterna(ind2) * estequio(k,ind) * P(ind)**(estequio(k,ind)-1.d0)
                            endif
                            
                         else
                            
                            ! And then, the rest of partial pressures in the molecule
                            if (dinterna(ind) == 0.d0) then
                               dinterna(ind) = P(ind2)**estequio(k,ind2)
                            else
                               dinterna(ind) = dinterna(ind) * P(ind2)**estequio(k,ind2)
                            endif
                            
                         endif
                         
                      endif
                      
                   enddo
                   
                endif
             enddo
             
             
             if (equilibrium(k) == 0.d0) then
                salida = 0.d0
                dinterna = 0.d0
             else
                if (charge(k) == 1) then
                   salida = salida + estequio(k,i)*interna / (equilibrium(k) * P_elec ) * &
                        equilibrium_atomic(1,minim)
                   gmat(i,:) = gmat(i,:) + estequio(k,i)*dinterna / (equilibrium(k) * P_elec ) * &
                        equilibrium_atomic(1,minim)
                else
                   salida = salida + estequio(k,i)*interna / equilibrium(k)
                   gmat(i,:) = gmat(i,:) + estequio(k,i)*dinterna / equilibrium(k)
                endif
             endif
             
          enddo
       endif
       
       ! Positive ions partial pressure
       salida = salida + equilibrium_atomic(1,i) * P(i) / P_elec
       
       ! Derivatives of positive ions partial pressure
       gmat(i,i) = gmat(i,i) + equilibrium_atomic(1,i) / P_elec
       
       ! Negative ions partial pressure
       salida = salida + 1.d0 / equilibrium_atomic(2,i) * P(i) * P_elec
       
       ! Derivatives of negative ions partial pressure
       gmat(i,i) = gmat(i,i) + 1.d0 / equilibrium_atomic(2,i) * P_elec
       
       ! P(i) = Pi + P+ + P- + Pmolec          
       fvec(i) = P(i) + salida - x0_sol(i)
       
       gmat(i,i) = gmat(i,i) + 1.d0
       gmat(i,22) = gmat(i,22) - abund_atom(i) / sum(abund_atom)
       
       ! Contribution to P_e of positive atomic ions
       fvec(22) = fvec(22) + equilibrium_atomic(1,i) * P(i) / P_elec
       
       gmat(22,i) = gmat(22,i) + equilibrium_atomic(1,i) / P_elec
       
       ! Contribution to P_e of negative atomic ions
       fvec(22) = fvec(22) - 1.d0 / equilibrium_atomic(2,i) * P(i) * P_elec
       
       gmat(22,i) = gmat(22,i) - 1.d0 / equilibrium_atomic(2,i) * P_elec
       
    enddo
    
    fvec(22) = fvec(22) - P_elec
    
  end subroutine funcv_Pg_from_T_Pe
  
  !-------------------------------------------------------------------
  ! Returns the value of the equations of the nonlinear set to be solved
  ! The equations are valid for obtaining Pe from Pgas and T
  ! P(22) is the electron pressure
  ! P(1:21) are the pressures of each element
  !-------------------------------------------------------------------
  subroutine funcv_Pe_from_T_Pg(x,n,fvec,gmat)
    integer :: n
    real(kind=8) :: x(n), fvec(n), gmat(n,n)
    integer :: i, j, k, l, m, ind, minim, ind2
    real(kind=8) :: P(n), salida, interna, P_e, minim_ioniz, dinterna(n)
    
    P = x
    
    fvec = 0.d0
    gmat = 0.d0
    
    ! We know that P_T = P(H)+P(He)+P(C)+...+Pe
    ! where P(i)=a(i)*P(H), with a(i) the abundance of element i with respect to H
    ! Therefore, P_T=K*P(H)+Pe, where K=sum(a(i)). Consequently, P(H) can be isolated to
    ! be P(H)=(P_T-Pe)/K
    ! Then, P(i) = a(i) * (P_T-Pe)/K
    x0_sol(1:21) = abund_atom * (P_total - P(22)) / sum(abund_atom)
    
    do i = 1, 21
       salida = 0.d0
       
       ! If temperature is very high, do not take into account molecular formation
       if (temper < 1.d5) then
          
          do j = 1, n_included
             k = which_included(j)
             interna = 0.d0
             dinterna = 0.d0
             interna = 1.d0
             
             minim = 0
             minim_ioniz = 100.d0
             
             ! Product of the partial pressures of the components of molecule k
             do l = 1, 4
                ind = composicion(k,l)
                
                if (ind /= 0.d0) then                  
                   if (pot_ion(ind) < minim_ioniz) then
                      minim = ind
                      minim_ioniz = pot_ion(ind)
                   endif
                   interna = interna*P(ind)**estequio(k,ind)
                   
                   ! Derivatives
                   do m = 1, 4
                      ind2 = composicion(k,m)
                      
                      if (ind2 /= 0.d0) then
                         
                         if (ind2 == ind) then
                            
                            ! Include the derivative of P(i) on df(i)/dP(i)
                            if (dinterna(ind) == 0.d0) then
                               dinterna(ind) = estequio(k,ind) * P(ind)**(estequio(k,ind)-1.d0)
                            else
                               dinterna(ind2) = dinterna(ind2) * estequio(k,ind) * P(ind)**(estequio(k,ind)-1.d0)
                            endif
                            
                         else
                            
                            ! And then, the rest of partial pressures in the molecule
                            if (dinterna(ind) == 0.d0) then
                               dinterna(ind) = P(ind2)**estequio(k,ind2)
                            else
                               dinterna(ind) = dinterna(ind) * P(ind2)**estequio(k,ind2)
                            endif
                            
                         endif
                         
                      endif
                      
                   enddo
                   
                endif
             enddo
             
             
             if (equilibrium(k) == 0.d0) then
                salida = 0.d0
             else
                if (charge(k) == 1) then
                   salida = salida + estequio(k,i)*interna / (equilibrium(k) * P(22) ) * &
                        equilibrium_atomic(1,minim)
                   gmat(i,:) = gmat(i,:) + estequio(k,i)*dinterna / (equilibrium(k) * P(22) ) * &
                        equilibrium_atomic(1,minim)
                   gmat(i,22) = gmat(i,22) - estequio(k,i)*interna / (equilibrium(k) * P(22)**2 ) * &
                        equilibrium_atomic(1,minim)
                else
                   salida = salida + estequio(k,i)*interna / equilibrium(k)
                   gmat(i,:) = gmat(i,:) + estequio(k,i)*dinterna / equilibrium(k)
                endif
             endif
             
          enddo
       endif
       
       
       ! Positive ions partial pressure
       salida = salida + equilibrium_atomic(1,i) * P(i) / P(22)
       
       ! Derivatives of positive ions partial pressure
       gmat(i,i) = gmat(i,i) + equilibrium_atomic(1,i) / P(22)
       gmat(i,22) = gmat(i,22) - equilibrium_atomic(1,i) * P(i) / P(22)**2
       
       
       ! Negative ions partial pressure
       salida = salida + 1.d0 / equilibrium_atomic(2,i) * P(i) * P(22)
       
       ! Derivatives of negative ions partial pressure
       gmat(i,i) = gmat(i,i) + 1.d0 / equilibrium_atomic(2,i) * P(22)
       gmat(i,22) = gmat(i,22) - 1.d0 / equilibrium_atomic(2,i) * P(i) / P(22)**2
       
       ! P(i) = Pi + P+ + P- + Pmolec          
       fvec(i) = P(i) + salida - x0_sol(i)
       
       gmat(i,i) = gmat(i,i) + 1.d0
       gmat(i,22) = -abund_atom(i) / sum(abund_atom)
       
       ! Contribution to P_e of positive atomic ions
       fvec(22) = fvec(22) + equilibrium_atomic(1,i) * P(i) / P(22)
       
       gmat(22,i) = gmat(22,i) + equilibrium_atomic(1,i) / P(22)
       gmat(22,22) = gmat(22,22) - equilibrium_atomic(1,i) * P(i) / P(22)**2
       
       ! Contribution to P_e of negative atomic ions
       fvec(22) = fvec(22) - 1.d0 / equilibrium_atomic(2,i) * P(i) * P(22)
       
       gmat(22,i) = gmat(22,i) - 1.d0 / equilibrium_atomic(2,i) * P(22)
       gmat(22,22) = gmat(22,22) - 1.d0 / equilibrium_atomic(2,i) * P(i)
       
    enddo
    
    ! Independent term: P_e = all contributors to electrons
    fvec(22) = fvec(22) - P(22)
    
    gmat(22,22) = gmat(22,22) - 1.d0
    
  end subroutine funcv_Pe_from_T_Pg
  
!-------------------------------------------------------------------
! Returns the value of the equations of the nonlinear set to be solved
! The equations are valid for obtaining Pe from Pgas and T
! P(22) is the electron pressure
! P(1:21) are the pressures of each element
!-------------------------------------------------------------------
  subroutine funcv_from_T_Pg_Pe(x,n,fvec,gmat)
    integer :: n
    real(kind=8) :: x(n), fvec(n), gmat(n,n)
    integer :: i, j, k, l, m, ind, minim, ind2
    real(kind=8) :: P(n), salida, interna, minim_ioniz, dinterna(n)
    
    P = x
    
    fvec = 0.d0
    gmat = 0.d0
    
    ! We know that P_T = P(H)+P(He)+P(C)+...+Pe
    ! where P(i)=a(i)*P(H), with a(i) the abundance of element i with respect to H
    ! Therefore, P_T=K*P(H)+Pe, where K=sum(a(i)). Consequently, P(H) can be isolated to
    ! be P(H)=(P_T-Pe)/K
    ! Then, P(i) = a(i) * (P_T-Pe)/K
    x0_sol(1:21) = abund_atom * (P_total - P_elec) / sum(abund_atom)
    
    do i = 1, 21
       salida = 0.d0
       
       ! If temperature is very high, do not take into account molecular formation
       if (temper < 1.d5) then
          
          do j = 1, n_included
             k = which_included(j)
             interna = 0.d0
             dinterna = 0.d0
             interna = 1.d0
             
             minim = 0
             minim_ioniz = 100.d0
             
             ! Product of the partial pressures of the components of molecule k
             do l = 1, 4
                ind = composicion(k,l)
                
                if (ind /= 0.d0) then
                   if (pot_ion(ind) < minim_ioniz) then
                      minim = ind
                      minim_ioniz = pot_ion(ind)
                   endif
                   interna = interna*P(ind)**estequio(k,ind)
                   
                   ! Derivatives
                   do m = 1, 4
                      ind2 = composicion(k,m)
                      
                      if (ind2 /= 0.d0) then
                         
                         if (ind2 == ind) then
                            
                            ! Include the derivative of P(i) on df(i)/dP(i)
                            if (dinterna(ind) == 0.d0) then
                               dinterna(ind) = estequio(k,ind) * P(ind)**(estequio(k,ind)-1.d0)
                            else
                               dinterna(ind2) = dinterna(ind2) * estequio(k,ind) * P(ind)**(estequio(k,ind)-1.d0)
                            endif
                            
                         else
                            
                            ! And then, the rest of partial pressures in the molecule
                            if (dinterna(ind) == 0.d0) then
                               dinterna(ind) = P(ind2)**estequio(k,ind2)
                            else
                               dinterna(ind) = dinterna(ind) * P(ind2)**estequio(k,ind2)
                            endif
                            
                         endif
                         
                      endif
                      
                   enddo
                   
                endif
             enddo
             
             
             if (equilibrium(k) == 0.d0) then
                salida = 0.d0
             else
                if (charge(k) == 1) then
                   salida = salida + estequio(k,i)*interna / (equilibrium(k) * P_elec ) * &
                        equilibrium_atomic(1,minim)
                   gmat(i,:) = gmat(i,:) + estequio(k,i)*dinterna / (equilibrium(k) * P_elec ) * &
                        equilibrium_atomic(1,minim)
                else
                   salida = salida + estequio(k,i)*interna / equilibrium(k)
                   gmat(i,:) = gmat(i,:) + estequio(k,i)*dinterna / equilibrium(k)
                endif
             endif
             
          enddo
       endif
       
       
       ! Positive ions partial pressure
       salida = salida + equilibrium_atomic(1,i) * P(i) / P_elec
       
       ! Derivatives of positive ions partial pressure
       gmat(i,i) = gmat(i,i) + equilibrium_atomic(1,i) / P_elec
       
       
       ! Negative ions partial pressure
       salida = salida + 1.d0 / equilibrium_atomic(2,i) * P(i) * P_elec
       
       ! Derivatives of negative ions partial pressure
       gmat(i,i) = gmat(i,i) + 1.d0 / equilibrium_atomic(2,i) * P_elec
       
       ! P(i) = Pi + P+ + P- + Pmolec
       fvec(i) = P(i) + salida - x0_sol(i)
       
       gmat(i,i) = gmat(i,i) + 1.d0       
    enddo
    
  end subroutine funcv_from_T_Pg_Pe
  
end module equations

module maths_chemical
  use equations
  Use Profiling
  implicit none
contains
  
  !-------------------------------------------------------------------
  ! Solves a system of nonlinear equations using the Newton mthod
  !-------------------------------------------------------------------
  subroutine mnewt(which,ntrial,x,n,tolx,tolf)
    Use nrtype
    Implicit None
    INTERFACE lubksb
       SUBROUTINE lubksb_dp(a,indx,b)
         USE nrtype
         REAL(DP), DIMENSION(:,:), INTENT(IN) :: a
         INTEGER(I4B), DIMENSION(:), INTENT(IN) :: indx
         REAL(DP), DIMENSION(:), INTENT(INOUT) :: b
       END SUBROUTINE lubksb_dp
       SUBROUTINE lubksb(a,indx,b)
         USE nrtype
         REAL(SP), DIMENSION(:,:), INTENT(IN) :: a
         INTEGER(I4B), DIMENSION(:), INTENT(IN) :: indx
         REAL(SP), DIMENSION(:), INTENT(INOUT) :: b
       END SUBROUTINE lubksb
    END INTERFACE
    INTERFACE ludcmp
       SUBROUTINE ludcmp_dp(a,indx,d)
         USE nrtype
         REAL(DP), DIMENSION(:,:), INTENT(INOUT) :: a
         INTEGER(I4B), DIMENSION(:), INTENT(OUT) :: indx
         REAL(DP), INTENT(OUT) :: d
       END SUBROUTINE ludcmp_dp
       SUBROUTINE ludcmp(a,indx,d)
         USE nrtype
         REAL(SP), DIMENSION(:,:), INTENT(INOUT) :: a
         INTEGER(I4B), DIMENSION(:), INTENT(OUT) :: indx
         REAL(SP), INTENT(OUT) :: d
       END SUBROUTINE ludcmp
    END INTERFACE
    integer :: which, n,ntrial
    real :: tolf, tolx
    real(kind=8) :: x(n),xold(n)
    integer :: i,k,indx(n)
    real(kind=8) :: d,errf,errx,fjac(n,n),fvec(n),p(n)
    real(kind=8) :: d8,fjac8(n,n),p8(n)
    real(kind=8) :: d4,fjac4(n,n),fvec4(n),p4(n)

    Call Time_routine('mnewt',.True.)

    do k=1,ntrial
       if (which == 1) then
          call funcv_Pe_from_T_Pg(x,n,fvec,fjac)   !User subroutine supplies function values at x in fvec
       else if (which == 2) then
          call funcv_Pg_from_T_Pe(x,n,fvec,fjac)   !User subroutine supplies function values at x in fvec
       else if (which == 3) then
          call funcv_from_T_Pg_Pe(x,n,fvec,fjac)   !User subroutine supplies function values at x in fvec 
       else
          Print *,'Error in mnewt'
          Stop
       endif
       
       errf=0.
       do i=1,n  !Check function convergence.
          errf=errf+abs(fvec(i))/(abs(x(i))+abs(fvec(i)))
       enddo
       if (errf <= tolf) then
          ntrial = k
          Call Time_routine('mnewt',.False.) 
          return
       endif
       p = -fvec

!       call ludcmp(fjac,indx,d) !Solve linear equations using LU decomposition
       
       fjac8=fjac
       call ludcmp(fjac8,indx,d8) !Solve linear equations using LU decomposition
       d=d8
!       fjac=fjac8


!       call lubksb(fjac,indx,p)
       
!       fjac8=fjac
       p8=p
       call lubksb(fjac8,indx,p8)
       p=p8

       errx=0.d0  ! Check root convergence.
       
       x = x + p ! Update solution
       
       If (which .eq. 1) then
          If (abs(p(22))/x(22) .lt. 1e-3) then ! Stopping criterion using relative change for Pe
             ntrial=k
             Call Time_routine('mnewt',.False.)
             Return
          End if
       End if
       
       do i=1,n  
          errx=errx+abs(p(i))/(abs(x(i))+abs(p(i)))
       enddo
       if(errx <= tolx) then
          ntrial = k
          Call Time_routine('mnewt',.False.)
          return
       endif
       
    enddo
    if (k == ntrial) then
       x = x0_sol
    endif
    Call Time_routine('mnewt',.False.)
  end subroutine mnewt
  
end module maths_chemical



Module Eq_state
  Use maths_chemical
  Use Param_structure
  Use Atomic_data
  Use Wittmann_eqstate
  Use Profiling
  Implicit None
  Private
  Public :: Compute_Pe, Compute_Pg, Compute_others_from_T_Pe_Pg, &
       eqstate_switch, eqstate_switch_others, eqstate_pe_consistency
  
Contains
  
  !-------------------------------------------------------------------
  ! Read the equilibrium constants and the molecular constitution
  !-------------------------------------------------------------------
  subroutine read_equil_cte
    Use Variables
    Implicit None
    Integer :: i, j, dif
    Character (len=256), Dimension(273) :: string
    Logical, Save :: FirstTime=.True.
    
    If (FirstTime) then
       FirstTime=.False.
       
       i=1
       String(i)='H 2/00                6.64618   -11.07680    -12.51163       -9.70592   '//&
            '  -3.35289      -5.14790       1.90866       -1.96784    0.25289'
       i=i+1
       String(i)='H 2/10                7.28102    -6.49325     -6.87854       -7.35273   '//&
            '  -4.72979      10.30859     -18.41065       11.96738   -3.27147'
       i=i+1
       String(i)='H 1F 1/00             5.40269   -14.39409    -16.24590      -11.85850   '//&
            '  -6.90834      -3.34336      -0.13194       -1.51033    0.17323'
       i=i+1
       String(i)='H 1F 1/10            10.23749    -2.90532     -0.54827       -0.47085   '//&
            '  -0.51781       0.00301      -0.50791       -0.27902    0.31787'
       i=i+1
       String(i)='H 1Cl1/00             6.45314   -11.00276    -12.37229       -9.19214   '//&
            '  -4.40882      -4.41388       1.95769       -2.11555    0.28703'
       i=i+1
       String(i)='H 1Cl1/10             9.30283    -4.03813     -2.23931       -2.68138   '//&
            '  -1.40488      -6.61984      12.43511      -10.01919    2.78346'
       i=i+1
       String(i)='He1H 1/10             8.31800    -5.02317     -4.47477       -5.21912   '//&
            '  -5.23915      10.92401     -15.19072        8.44209   -1.99171'
       i=i+1
       String(i)='He2/10                7.83866    -5.97679     -6.09837       -6.55943   '//&
            '  -2.58726       5.36980     -13.48444       10.26817   -3.20575'
       i=i+1
       String(i)='C 1H 1/00             7.04641    -8.49562     -9.63745       -8.30710   '//&
            '  -1.72875      -4.09372       0.94498       -1.01589    0.04693'
       i=i+1
       String(i)='C 1H 1/10             6.72106    -9.28895    -12.11067      -11.25678   '//&
            '   2.04679      -4.36831      -7.91721        7.85487   -2.76797'
       i=i+1
       String(i)='C 2/00                5.24759   -14.74485    -16.644193     -12.635250  '//&
            '  -7.27361      -3.35230      -1.28030       -0.40357   -0.177749'
       i=i+1
       String(i)='C 2/10                6.10593   -12.96702    -14.32206      -10.86910   '//&
            '  -6.27432      -2.87521      -1.29507        0.03051   -0.32503'
       i=i+1
       String(i)='C 1N 1/00             3.68661   -18.34535    -21.14268      -16.81865   '//&
            '  -6.72026      -5.13231      -4.38504        3.05068   -1.47898'
       i=i+1
       String(i)='C 1N 1/10             6.66439   -11.48041    -13.39683      -11.43315   '//&
            '  -3.53052      -0.92988      -7.66507        5.59301   -1.91477'
       i=i+1
       String(i)='C 1O 1/00             1.13500   -26.41735    -29.67737      -22.64423   '//&
            ' -13.19676      -5.52344      -3.04468        0.17280   -0.71347'
       i=i+1
       String(i)='C 1O 1/10             3.40377   -19.94999    -22.80141      -16.03858   '//&
            ' -11.61324      -2.68415      -2.71942       -0.02213   -0.44281'
       i=i+1
       String(i)='C 1F 1/00             5.48321   -13.70874    -15.43227      -11.26520   '//&
            '  -7.15597      -2.61576      -1.57773        0.02894   -0.32488'
       i=i+1
       String(i)='C 1Al1/00             7.06944    -8.84775     -9.59790       -8.10604   '//&
            '  -2.09047      -5.88164       3.08754       -2.15132    0.27966'
       i=i+1
       String(i)='C 1P 1/00             5.77522   -12.82154    -13.79619      -12.12930   '//&
            '  -7.60224       6.16419     -14.55918        8.40417   -2.31794'
       i=i+1
       String(i)='C 1S 1/00             4.47326   -17.74866    -19.98104      -13.50181   '//&
            ' -13.03317       3.61561      -9.48157        4.21581   -1.39268'
       i=i+1
       String(i)='C 1S 1/10             4.82429   -15.21924    -17.59749      -13.03214   '//&
            '  -4.40978     -10.66405       5.59652       -3.4053     0.26213'
       i=i+1
       String(i)='C 1Cl1/00             7.46017    -8.32053     -8.98762       -7.59473   '//&
            '  -1.65267      -5.31566       2.22799       -1.41944    0.08502'
       i=i+1
       String(i)='N 1H 1/00             6.97413    -8.73658     -9.52808       -8.15268   '//&
            '  -0.81310      -7.97647       5.86085       -3.83666    0.66869'
       i=i+1
       String(i)='N 1H 1/10             6.55405    -8.48028     -9.27848       -7.93444   '//&
            '  -0.88061      -7.44300       5.90140       -3.84626    0.67015'
       i=i+1
       String(i)='N 2/00                2.12100   -23.39808    -25.62272      -20.52272   '//&
            ' -11.53413     -5.06591       -2.32029       -0.10375   -0.56480'
       i=i+1
       String(i)='N 2/10                3.08250   -20.42213    -24.03239      -18.66966   '//&
            '  -7.00811     -7.50577       -2.74468        2.11890   -1.35307'
       i=i+1
       String(i)='N 1O 1/00             4.72528   -15.76210    -17.25354      -13.52989   '//&
            '  -7.78905      -3.18062     -1.87891         0.23489   -0.46874'
       i=i+1
       String(i)='N 1O 1/10             0.76310   -25.86461    -28.79738      -22.46610   '//&
            ' -12.83108      -5.62150      -2.61207       -0.10776   -0.62484'
       i=i+1
       String(i)='N 1F 1/00             7.34671    -8.70158     -9.23939       -8.11084   '//&
            '  -2.19012     -5.0155        2.01086       -1.40606    0.08902'
       i=i+1
       String(i)='N 1S 1/00             6.11321   -11.83829    -12.64856      -10.09332   '//&
            '  -5.49976      -2.92950      -0.77616       -0.21521   -0.23388'
       i=i+1
       String(i)='O 1H 1/00             6.39180   -10.92203    -12.25273       -9.00489   '//&
            '  -4.44986      -4.05325       1.71374       -2.13312    0.33423'
       i=i+1
       String(i)='O 1H 1/10             5.37870   -12.34764    -14.57228       -9.44684   '//&
            '  -6.26092      -4.94877       3.39295       -3.54582    0.66513'
       i=i+1
       String(i)='O 1H 1/01             6.44237   -11.75031    -13.25662       -9.68241   '//&
            '  -5.25845      -3.57491       0.91507       -1.73859    0.22280'
       i=i+1
       String(i)='O 2/00                6.73818   -12.31646    -14.22766      -10.46686   '//&
            '  -5.63130      -2.53073      -2.52499        1.22132   -0.67470'
       i=i+1
       String(i)='O 2/10                4.90252   -16.06404    -18.00438      -13.31531   '//&
            '  -8.72738      -1.96728      -3.25503        0.97322   -0.64978'
       i=i+1
       String(i)='F 1O 1/00             8.81327    -5.86986     -5.49551       -5.79462   '//&
            '  -3.00638       3.27812      -7.36000        4.48784   -1.25662'
       i=i+1
       String(i)='F 2/00               10.08792    -4.61013     -3.51767       -3.80151   '//&
            '  -5.23790       6.19663      -6.33357        2.15346   -0.31359'
       i=i+1
       String(i)='Na1H 1/00             7.85907    -5.15060     -3.18497       -7.36946   '//&
            '  -3.91247       9.88835     -13.45574        7.34407   -1.73771'
       i=i+1
       String(i)='Na1O 1/00             7.36023    -6.72990     -5.51727       -9.05245   '//&
            '   0.05800      -0.86488      -3.31694        2.27394   -0.80055'
       i=i+1
       String(i)='Na1F 1/00             5.10011   -12.78493    -13.69076      -12.82689   '//&
            '  -3.94906      -5.65787       2.63362       -2.63211    0.37490'
       i=i+1
       String(i)='Na2/00                8.91434    -3.51557      1.25232       -6.09650   '//&
            '   3.15702      -1.84918      -1.60328        3.10365   -1.28354'
       i=i+1
       String(i)='Na1Cl1/00             5.83610   -10.01911    -10.68549      -12.78745   '//&
            '   2.70262     -10.29517       4.11301       -1.32833   -0.23863'
       i=i+1
       String(i)='Na1K 1/00             8.50091    -3.79730      2.15758       -6.40856   '//&
            '   1.89432       2.47884      -5.62826        3.97661   -1.01701'
       i=i+1
       String(i)='Mg1H 1/00             7.94460    -3.44416     -3.67427       -4.28914   '//&
            '  -0.26480      -0.72336      -0.27626       -0.08708   -0.03835'
       i=i+1
       String(i)='Mg1H 1/10             7.92940    -5.48016     -5.08525       -5.67242   '//&
            '  -3.61181       5.93270     -10.60764        6.56008   -1.77205'
       i=i+1
       String(i)='Mg1N 1/00             6.07874    -8.41429     -8.18790       -9.76675   '//&
            '   0.21759      -7.18378       4.47052       -2.81572    0.42687'
       i=i+1
       String(i)='Mg1O 1/00             6.53029    -8.66429     -9.02210      -10.54685   '//&
            '   0.87870     -14.81334      17.72098      -12.22165    2.79458'
       i=i+1
       String(i)='Mg1F 1/00             5.27837   -11.41905    -12.52272      -10.92282   '//&
            '  -3.72537      -5.65874       3.27630       -2.95587    0.49120'
       i=i+1
       String(i)='Mg1F 1/10             5.92089   -11.22365    -13.16768       -9.14801   '//&
            '  -4.96356      -5.28108       2.71766       -2.56560    0.39152'
       i=i+1
       String(i)='Mg2/00               10.07619    -2.79223      1.58848       -3.62550   '//&
            '   2.50033        0.0062      -0.03699        0.02717   -0.01356'
       i=i+1
       String(i)='Mg1S 1/00             7.05864    -5.85489     -4.39106       -6.96260   '//&
            '  -8.02559      21.94729     -35.66202       23.26647   -5.76056'
       i=i+1
       String(i)='Mg1Cl1/00             6.41454    -8.12922     -8.16934       -9.38001   '//&
            '   0.35616      -6.60165       3.55989       -2.12881    0.24093'
       i=i+1
       String(i)='Al1H 1/00             7.51786    -7.22520     -7.70051       -7.59779   '//&
            '  -0.51722      -4.32852       0.11858        0.51557   -0.47718'
       i=i+1
       String(i)='Al1H 1/10             8.47879    -3.56783     -1.71353       -2.26004   '//&
            '   0.15636     -10.53761      16.32245      -11.23074    2.75663'
       i=i+1
       String(i)='Al1N 1/00             7.28116    -7.17859     -7.05692       -7.61788   '//&
            '  -1.08656      -3.27278      -0.73586        0.75869   -0.46513'
       i=i+1
       String(i)='Al1O 1/00             5.68022   -12.03343    -14.38874      -10.70400   '//&
            ' -10.79607       5.96587      -6.79116        0.18078    0.33268'
       i=i+1
       String(i)='Al1O 1/10             7.93766    -4.78683     -3.66152       -4.06650   '//&
            '  -4.81935       5.21269      -6.02346        2.41828   -0.48715'
       i=i+1
       String(i)='Al1F 1/00             4.32848   -16.35738    -18.82876      -12.97202   '//&
            ' -10.78485      -0.08565      -4.63279        1.25995   -0.61835'
       i=i+1
       String(i)='Al1F 1/10             7.22176    -7.58069     -8.05318       -7.19521   '//&
            '  -1.79323      -3.29501      -0.17692        0.15156   -0.28668'
       i=i+1
       String(i)='Al2/00                8.80490    -4.28397     -2.74600       -3.91030   '//&
            '  -8.97462      14.98145     -14.75012        5.77213   -0.84691'
       i=i+1
       String(i)='Al1S 1/00             6.76619    -8.85195    -10.01474       -8.98695   '//&
            '  -3.85079      -7.39216      11.72266      -10.91696    3.03168'
       i=i+1
       String(i)='Al1Cl1/00             5.70948   -12.19987    -14.30787       -9.24395   '//&
            '  -7.53767      -2.77114       0.63374       -1.84937    0.27216'
       i=i+1
       String(i)='Si1H 1/00             7.25177    -7.81321     -8.03737       -7.34499   '//&
            '  -0.83588      -4.58628       0.92336       -0.16717   -0.29793'
       i=i+1
       String(i)='Si1H 1/10             7.48433    -8.01425     -8.73292       -7.42921   '//&
            '  -1.68306      -4.40365       1.32213       -0.74172   -0.11991'
       i=i+1
       String(i)='Si1C 1/00             6.16790   -11.24960    -12.38738       -9.74498   '//&
            '  -5.23196      -2.74507      -0.19090       -1.03168    0.08490'
       i=i+1
       String(i)='Si1N 1/00             5.13422   -13.43147    -14.78981      -10.91429   '//&
            '  -8.87338       1.14522      -8.05858        5.40492   -1.91649'
       i=i+1
       String(i)='Si1O 1/00             3.61413   -19.85093    -22.26364      -16.05708   '//&
            ' -12.29117       0.38896      -7.20703        2.95515   -1.17621'
       i=i+1
       String(i)='Si1O 1/10             6.32803   -12.11774    -13.66978      -10.00743   '//&
            '  -6.01638      -2.77938      -0.89967       -0.25664   -0.21405'
       i=i+1
       String(i)='Si1F 1/00             5.33411   -13.49037    -15.20604      -10.75001   '//&
            '  -7.66313      -1.62951      -2.36709        0.36117   -0.36815'
       i=i+1
       String(i)='Si2/00                7.58247    -7.77222     -7.96268       -7.66853   '//&
            '  -1.80827      -3.24297      -1.89133        2.24185   -1.03491'
       i=i+1
       String(i)='Si1S 1/00             5.16109   -15.56600    -17.18651      -12.50534   '//&
            '  -9.05399      -0.67796      -4.43768        1.55549   -0.71820'
       i=i+1
       String(i)='Si1Cl1/00             6.64118    -9.68492    -10.52210       -8.31865   '//&
            '  -3.32634      -4.34153       1.30686       -1.26850    0.06779'
       i=i+1
       String(i)='P 1H 1/00             7.11102    -7.91770     -7.54698       -7.80237   '//&
            '  -1.14931      -4.51717       1.27985       -0.59061   -0.16733'
       i=i+1
       String(i)='P 1H 1/00             6.94052    -8.50473     -9.13869       -7.88838   '//&
            '  -1.61359      -5.53605       2.70457       -1.67172    0.09913'
       i=i+1
       String(i)='P 1N 1/00             5.10497   -15.09921    -15.51883      -13.22497   '//&
            '  -7.39313      -2.89443      -1.96529        0.30433   -0.43627'
       i=i+1
       String(i)='P 1O 1/00             4.82389   -15.07670    -15.90810      -12.80597   '//&
            '  -7.83529      -2.23049      -2.63062        0.63908   -0.50960'
       i=i+1
       String(i)='P 1F 1/00             6.06229   -11.24789    -12.06266      -10.11950   '//&
            '  -4.52914      -3.08371      -1.31984        0.34854   -0.36703'
       i=i+1
       String(i)='P 1F 1/10             5.78415   -12.87458    -14.15352      -10.94911   '//&
            '  -6.15561      -2.96418      -1.12239       -0.12336   -0.27232'
       i=i+1
       String(i)='P 2/00                6.20877   -12.58353    -12.95927       -9.31525   '//&
            '  -7.92812      -3.20998       2.05041       -2.93863    0.58042'
       i=i+1
       String(i)='P 2/10                5.76557   -12.28456    -12.83399      -10.23892   '//&
            '  -6.10782      -3.37092       0.36165       -1.10629   -0.01598'
       i=i+1
       String(i)='P 1S 1/00             6.10990   -11.37745    -11.49425       -9.83115   '//&
            '  -4.78712      -3.53665       0.09103       -0.73559   -0.08102'
       i=i+1
       String(i)='P 1Cl1/00             7.21540    -8.15873     -7.76881       -7.87986   '//&
            '  -1.72798      -4.03493       0.63691       -0.39611   -0.15901'
       i=i+1
       String(i)='S 1H 1/00             6.87419    -8.93220     -9.79302       -7.87885   '//&
            '  -1.98438      -5.84405       3.43256       -2.39716    0.30651'
       i=i+1
       String(i)='S 1H 1/10             6.04269   -10.27875    -11.04178       -8.94793   '//&
            '  -3.68852      -5.03704       2.60563       -2.19035    0.26231'
       i=i+1
       String(i)='S 1O 1/00             5.95089   -12.88406    -14.69913      -11.18507   '//&
            '  -6.09006      -1.73361      -3.54751        1.53092   -0.68577'
       i=i+1
       String(i)='S 1F 1/00             7.37327    -8.73956     -9.43723       -7.81428   '//&
            '  -2.34082      -4.66032       1.59783       -1.22035    0.05082'
       i=i+1
       String(i)='S 1F 1/10             6.87878    -9.43083     -9.81411       -8.59311   '//&
            '  -3.02439      -4.49452       1.44370       -1.26087    0.06564'
       i=i+1
       String(i)='S 2/00                6.89619   -10.50437    -12.10022       -9.10398   '//&
            '  -4.59772      -3.13188       0.23007       -1.22386    0.15600'
       i=i+1
       String(i)='S 1Cl1/00             8.10093    -6.44164     -6.14206       -6.22985   '//&
            '  -2.31553       0.79412      -4.75882        2.94702   -0.91893'
       i=i+1
       String(i)='S 1Cl1/10             6.87821    -8.76274     -8.95910       -8.21321   '//&
            '  -2.23724      -4.73894       1.63123       -1.20764    0.04569'
       i=i+1
       String(i)='Cl1O 1/00             8.12418    -6.96838     -7.15736       -6.83330   '//&
            '  -1.58182      -1.90586      -2.04608        1.45892   -0.61162'
       i=i+1
       String(i)='Cl1F 1/00             8.60707    -6.62162     -7.03245       -6.68880   '//&
            '  -0.26567      -4.37830       0.62657        0.08640   -0.31348'
       i=i+1
       String(i)='Cl2/00                8.80279    -6.38380     -6.41655       -6.40016   '//&
            '  -1.62613      -0.44883      -3.73213        2.54886   -0.86037'
       i=i+1
       String(i)='Cl2/10                7.05492    -9.70967    -10.66077       -8.39042   '//&
            '  -3.29182      -4.58698       1.58193       -1.51848    0.14881'
       i=i+1
       String(i)='K 1H 1/00             7.69175    -5.35797     -2.26451       -8.08608   '//&
            '  -4.26215      11.34036     -15.14885        8.26714   -1.93014'
       i=i+1
       String(i)='K 1O 1/00             7.27961    -6.11961     -3.90978      -10.85040   '//&
            '  -1.01165      11.42403     -22.98035       15.96920   -4.88467'
       i=i+1
       String(i)='K 1F 1/00             5.18726   -12.24978    -12.29430      -14.75464   '//&
            '   2.62056     -15.20304      10.73943       -5.98584    0.92568'
       i=i+1
       String(i)='K 1Cl1/00             5.59156   -10.54338     -9.98224      -14.17293   '//&
            '   2.16516      -6.96062      -1.15560        2.23859   -1.17212'
       i=i+1
       String(i)='K 2/00                9.05658    -3.90563      3.24458       -6.85498   '//&
            '   1.90425       3.68922      -7.23052        5.11262   -1.31893'
       i=i+1
       String(i)='Ca1H 1/00             7.55235    -5.50770     -1.17712       -7.73041   '//&
            '  -3.56919       7.02675      -8.30665        3.73578   -0.77740'
       i=i+1
       String(i)='Ca1O 1/00             6.07907    -9.27907     -8.31684      -15.11454   '//&
            ' -23.24821      78.39928    -115.31054       74.04032  -18.73513'
       i=i+1
       String(i)='Ca1F 1/00             4.48126   -13.67980    -12.90930      -13.45853   '//&
            '  -5.11285      -5.53255       3.26883       -3.30927    0.56818'
       i=i+1
       String(i)='Ca1S 1/00             6.32990    -7.87225     -5.90392      -11.69176   '//&
            ' -23.78964      54.54238     -58.59651       26.21900   -4.38236'
       i=i+1
       String(i)='Ca1Cl1/00             5.55349   -10.51365     -8.91567      -11.64325   '//&
            '  -1.43326      -7.22308       5.32969       -3.95644    0.74541'
       i=i+1
       String(i)='Ca2/00                9.52903    -4.10508      5.06073       -7.15721   '//&
            '   3.24307      -0.03427      -0.05995        0.04697   -0.04860'
       i=i+1
       String(i)='Ti1H 1/10             7.92701    -6.20829     -6.17669       -6.37999   '//&
            '  -1.99592       0.95195      -5.41345        3.70171   -1.16519'
       i=i+1
       String(i)='Ti1O 1/00             4.54622   -17.06111    -17.57560      -14.09174   '//&
            '  -7.99227      -6.52097       3.06759       -3.31400    0.46430'
       i=i+1
       String(i)='Ti1F 1/00             4.68510   -16.12598    -16.10659      -13.36247   '//&
            '  -8.10931      -3.55280      -0.72704       -0.81226   -0.12180'
       i=i+1
       String(i)='Ti1S 1/00             6.36880   -12.33948    -11.69968      -10.47954   '//&
            '  -3.74515      -6.83823       3.37494       -2.44968    0.26181'
       i=i+1
       String(i)='Ti1Cl1/00             6.13633   -11.72255    -10.42460      -10.94377   '//&
            '  -8.24643       7.18628     -12.43153        6.07257   -1.52108'
       i=i+1
       String(i)='Cr1H 1/00             7.00380    -7.82805     -6.05590       -9.72033   '//&
            '   4.08850     -10.95678       4.61466       -0.66400   -0.47153'
       i=i+1
       String(i)='Cr1N 1/00             7.04685   -10.37543     -7.84522       -9.80594   '//&
            '  -3.23721      -3.96450       0.84501       -0.89420   -0.02408'
       i=i+1
       String(i)='Cr1O 1/00             6.05745   -12.23054    -11.16902      -10.10099   '//&
            '  -5.21941      -5.62584       3.61837       -3.24405   -0.57119'
       i=i+1
       String(i)='Mn1H 1/00             7.07056    -6.61329     -4.83597      -10.15173   '//&
            '   1.43828      -1.01071      -4.62221        3.80490   -1.30302'
       i=i+1
       String(i)='Mn1O 1/00             6.95781    -9.42834     -8.35984      -11.07662   '//&
            '  -0.55767      -5.79294       3.18631       -2.32005    0.32932'
       i=i+1
       String(i)='Fe1H 1/00             8.45947    -6.10358     -4.91048       -9.13663   '//&
            ' -10.42726      31.03266     -43.84669       26.53631   -6.50937'
       i=i+1
       String(i)='Fe1O 1/00             6.95616   -10.64869    -10.20363       -9.76137   '//&
            '  -3.89564      -4.69479       2.42672       -2.39854    0.38391'
       i=i+1
       String(i)='Fe1F 1/00             6.37591   -11.84136    -11.63085      -10.24416   '//&
            '  -5.09600      -3.49503       0.10301       -0.80943   -0.05749'
       i=i+1
       String(i)='Fe1S 1/00             7.61887    -8.86847     -7.84584       -8.39911   '//&
            '  -1.55148      -5.26284       2.09605       -1.32312    0.06008'
       i=i+1
       String(i)='Fe1Cl1/00             7.72101    -7.62079     -6.39094       -7.94184   '//&
            '  -0.77987      -3.31418      -1.00004        1.05721   -0.56481'
       i=i+1
       String(i)='Ni1H 1/00             7.54272    -7.84484     -8.08272       -8.33053   '//&
            '  -1.17109      -0.69095      -5.31219        3.85059   -1.29049'
       i=i+1
       String(i)='Ni1O 1/00             7.84427    -9.77196    -10.43476       -8.45592   '//&
            '  -3.14171      -4.73552       1.77058       -1.50388    0.12496'
       i=i+1
       String(i)='Cu1H 1/00             7.49122    -7.31103     -6.30409       -6.43034   '//&
            '  -0.66713      -3.03892      -1.35262        1.45859   -0.70899'
       i=i+1
       String(i)='Cu1O 1/00             7.51122    -7.32301     -6.26863       -6.40429   '//&
            '  -0.61138      -3.50479      -0.82929        0.99370   -0.55257'
       i=i+1
       String(i)='Cu1F 1/00             6.27887   -10.87880    -11.78989       -7.48977   '//&
            '  -2.88614     -10.88488      10.36143       -7.33720    1.59397'
       i=i+1
       String(i)='Cu1S 1/00             7.33673    -7.50640     -6.11035       -6.13204   '//&
            '  -1.54646      -2.33456      -1.45137        1.01823   -0.50010'
       i=i+1
       String(i)='Cu1Cl1/00             6.55496    -9.84989    -10.16302       -6.88849   '//&
            '  -2.74382      -8.29425       7.17816       -5.20030    1.08247'
       i=i+1
       String(i)='Cu2/00                8.18657    -6.14083     -2.61244       -3.84602   '//&
            '  -4.82393       8.31217     -12.63322        7.27609   -1.83010'
       i=i+1
       String(i)='Si1C 2/00            13.04886   -23.46701    -25.76029      -19.87791   '//&
            ' -11.43562      -4.95066      -2.54654        0.10690   -0.59353'
       i=i+1
       String(i)='H 1N 1C 1/00         13.21232   -23.58285    -26.42461      -20.66952   '//&
            ' -11.47412      -5.38767      -1.45619       -0.94148   -0.30466'
       i=i+1
       String(i)='H 2O 1/00            12.97286   -23.37501    -26.36798      -19.92380   '//&
            ' -10.95044      -5.01260      -1.05600       -1.64857    0.00000'
       i=i+1
       String(i)='H 1C 1N 1/00          9.88113   -31.07390    -33.87063      -35.06000   '//&
            '   0.33699     -20.10714       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='H 1C 1O 1/00         10.77025   -28.27480    -31.65565      -24.45597   '//&
            ' -14.02317      -5.68687      -3.09130        0.04791   -0.71720'
       i=i+1
       String(i)='H 1C 1O 1/10          8.29981   -35.11483    -41.52652      -21.97425   '//&
            ' -40.49950      19.41979     -16.24040        0.00000    0.00000'
       i=i+1
       String(i)='H 1C 1P 1/00         11.28075   -26.92730    -30.37835      -22.27413   '//&
            ' -19.66180       4.62985     -10.68176        2.21919   -0.64697'
       i=i+1
       String(i)='H 1N 1O 1/00         13.82334   -21.18646    -22.02749      -24.60506   '//&
            '   2.03575     -14.04077       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='C 1H 2/00            13.91579   -19.37139    -21.54940      -16.56192   '//&
            '  -9.28425      -4.29288      -0.99104       -0.56210   -0.44508'
       i=i+1
       String(i)='C 2H 1/00            10.75728   -28.45609    -32.93898      -25.68086   '//&
            ' -13.33929      -5.17827      -6.15055        2.54163   -1.44958'
       i=i+1
       String(i)='C 3/00               10.43409   -33.26115    -36.65810      -28.30068   '//&
            ' -16.11478      -9.49905       3.19178       -6.56281    1.48080'
       i=i+1
       String(i)='C 2O 1/00             9.05074   -33.58063    -37.11909      -36.97258   '//&
            '  -2.15508     -20.89652       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='C 2N 1/00             9.06657   -32.66106    -35.26121      -36.78007   '//&
            '  -0.39594     -21.18791       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='C 1N 2/00            11.98214   -26.42304    -27.12281      -34.32401   '//&
            '   6.53414     -20.03990       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='C 1O 2/00             8.39177   -38.87688    -44.42014      -34.43134   '//&
            ' -20.17805      -6.83693      -6.23712        1.22020   -1.27517'
       i=i+1
       String(i)='C 1O 1F 1/00         10.69836   -29.95995    -33.44015      -26.08100   '//&
            ' -15.21448      -5.45070      -4.25881        0.58553   -0.85453'
       i=i+1
       String(i)='C 1O 1S 1/00          9.97795   -33.36350    -38.06186      -29.26385   '//&
            ' -20.03873       3.95451     -23.44653       17.12142   -6.58352'
       i=i+1
       String(i)='C 1O 1Cl1/00         10.64077   -28.32895    -31.55902      -24.69648   '//&
            ' -13.81496      -6.98848      -0.87238       -2.03479    0.00000'
       i=i+1
       String(i)='C 1F 2/00            12.56105   -25.94986    -29.68451      -21.69473   '//&
            ' -12.47749     -10.29903       5.40428       -6.31327    1.27655'
       i=i+1
       String(i)='C 1S 2/00            12.21262   -27.91401    -31.67064      -24.74712   '//&
            ' -13.39383      -9.31892       1.75886       -3.01735    0.00000'
       i=i+1
       String(i)='C 1Cl2/00            14.91700   -17.43075    -19.62013      -15.79339   '//&
            '  -7.84794     -12.90377      16.53531      -14.39179    3.58949'
       i=i+1
       String(i)='N 1H 2/00            14.28988   -18.18765    -19.67940      -21.32839   '//&
            '   3.20435     -12.73523       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='N 2C 1/00            10.90900   -28.92856    -30.05428      -36.80345   '//&
            '   5.72649     -21.52711       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='N 1C 1O 1/00         10.26117   -31.08905    -33.64285      -35.13077   '//&
            '  -0.07525     -20.12807       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='N 3/00               12.65275   -24.55511    -24.11137      -36.50836   '//&
            '  12.61348     -21.91534       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='N 2O 1/00            12.45129   -27.17699    -28.17480      -35.12609   '//&
            '   6.31977     -20.52033       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='O 3/00               17.59693   -15.07998    -16.70156      -13.27507   '//&
            '  -7.90765      -0.05353      -6.95294        4.17366   -1.59216'
       i=i+1
       String(i)='O 1Al1F 1/00         10.65398   -29.81895    -34.07474      -26.87034   '//&
            ' -13.96093      -8.19320      -1.99592       -0.70903   -1.23457'
       i=i+1
       String(i)='O 1Al1Cl1/00         12.29924   -25.24720    -28.80369      -22.83125   '//&
            ' -11.48773      -7.57022      -0.75421       -1.28615   -0.25068'
       i=i+1
       String(i)='O 1Ti1F 1/00         11.03130   -30.69450    -32.94160      -21.34850   '//&
            ' -33.41800      16.81690     -14.43910        0.00000    0.00000'
       i=i+1
       String(i)='O 1Ti1Cl1/00         12.15495   -27.17434    -28.31784      -23.75274   '//&
            ' -15.93328      -0.23044      -8.87391        3.75541   -1.68906'
       i=i+1
       String(i)='F 1C 1N 1/00         10.97168   -29.98148    -32.46821      -33.92875   '//&
            '   0.11733     -19.48451       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='Na1O 1H 1/00         13.31166   -19.02463    -20.72009      -18.91732   '//&
            '  -5.21369      -7.91596      -0.07049       -0.35216   -0.55314'
       i=i+1
       String(i)='Mg1O 1H 1/00         13.24097   -19.19626    -21.12673      -18.67745   '//&
            '  -6.37721      -5.45881      -3.81078        2.57661   -1.46552'
       i=i+1
       String(i)='Mg1F 2/00            11.11597   -25.37244    -27.83549      -23.94929   '//&
            '  -9.00127      -8.15010      -3.51713        2.32791   -1.59965'
       i=i+1
       String(i)='Mg1Cl2/00            12.84690   -18.95419    -21.00457      -18.73271   '//&
            '  -5.45995      -8.51413       0.26641       -0.31294   -0.60550'
       i=i+1
       String(i)='Al1O 1H 1/00         13.11208   -24.06571    -27.52393      -18.63797   '//&
            ' -20.22825       6.73222      -8.78240        0.00000    0.00000'
       i=i+1
       String(i)='Al1O 1H 1/10         13.01664   -20.60587    -23.43152      -18.22785   '//&
            '  -9.77028      -4.47228      -2.20760        0.03772   -0.52372'
       i=i+1
       String(i)='Al1O 2/00            13.24653   -21.95983    -25.23185      -19.71143   '//&
            ' -10.13389      -6.45765      -1.35601       -0.23623   -0.57039'
       i=i+1
       String(i)='Al1F 2/00            10.07074   -28.86724    -32.71615      -25.03692   '//&
            ' -13.78314      -8.44361      -0.04511       -2.29428    0.00000'
       i=i+1
       String(i)='Al2O 2/00            11.88563   -25.30513    -28.87802      -23.02585   '//&
            ' -11.07206      -8.70778       0.56102       -2.18134    0.00000'
       i=i+1
       String(i)='Al1Cl1F 1/00         11.06233   -24.97909    -28.21849      -21.48938   '//&
            ' -13.45846      -0.39048     -13.09560        9.63596   -3.95523'
       i=i+1
       String(i)='Al1Cl2/00            12.74760   -20.99436    -23.64684      -18.18375   '//&
            '  -8.22689     -12.22377      10.71669      -10.62258    2.89173'
       i=i+1
       String(i)='Si1O 2/00            11.45452   -30.39907    -34.36670      -26.83801   '//&
            ' -15.44214      -5.61871      -5.92886        2.61137   -1.66447'
       i=i+1
       String(i)='Si1F 2/00            10.61891   -29.37800    -33.01435      -24.82501   '//&
            ' -15.54870      -5.38021      -4.58642        1.40555   -1.23454'
       i=i+1
       String(i)='Si2C 1/00            12.60058   -25.84013    -30.83960      -23.25548   '//&
            '  -5.78255     -20.68797       8.93310       -2.86206   -1.08303'
       i=i+1
       String(i)='Si2N 1/00            12.58289   -23.82169    -25.25733      -26.79754   '//&
            '   0.12040     -15.60999       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='Si3/00               15.29684   -17.28461    -19.97404      -14.76497   '//&
            '  -6.44264      -8.99033       1.12841        0.68859   -1.28512'
       i=i+1
       String(i)='Si1Cl2/00            13.32914   -21.35277    -23.90839      -17.33491   '//&
            ' -11.78213      -4.53376      -0.63538       -1.61860    0.00000'
       i=i+1
       String(i)='P 1H 2/00            12.82560   -14.24100    -10.19100      -68.38930   '//&
            '  18.41000     -26.94800      11.21900        0.00000    0.00000'
       i=i+1
       String(i)='P 1O 2/00            11.47264   -27.99984    -30.18853      -24.48097   '//&
            ' -16.67989       1.18804     -10.45044        3.66883   -1.34375'
       i=i+1
       String(i)='S 1H 2/00            14.26297   -18.57621    -20.84889      -15.80825   '//&
            '  -7.96719      -6.92094       2.53352       -2.51140    0.00000'
       i=i+1
       String(i)='S 1F 2/00            15.40006   -18.27906    -20.13225      -15.75565   '//&
            '  -8.24158      -6.11033       1.03399       -1.80274    0.00000'
       i=i+1
       String(i)='S 1O 2/00            12.69698   -26.19675    -29.86507      -22.28419   '//&
            ' -14.09848      -4.94746      -3.21569       -0.09197   -0.49262'
       i=i+1
       String(i)='S 2O 1/00             7.14430   -17.64170    -22.76440      -13.41240   '//&
            '  -2.93276     -76.39850     137.06300      -83.44470    0.00000'
       i=i+1
       String(i)='S 3/00               15.97889   -18.59412    -19.99498      -13.93973   '//&
            '  -7.48137      -8.18017       3.99743       -2.90661    0.00000'
       i=i+1
       String(i)='S 1Cl2/00            16.73426   -13.62348    -14.81222      -11.40476   '//&
            '  -6.36709      -4.19719       0.83514       -1.43001    0.00000'
       i=i+1
       String(i)='Cl1C 1N 1/00         11.15157   -28.19659    -31.21543      -32.22215   '//&
            '   0.33539     -18.66323       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='Cl1O 2/00            17.75465   -12.85440    -13.51044      -16.49023   '//&
            '   3.97583     -10.13898       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='Cl2O 2/00            18.47826   -10.35973    -12.21508       -3.66387   '//&
            ' -12.13139       0.00000       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='K 1C 1N 1/00          9.60526   -29.43319    -29.77845      -36.27566   '//&
            '   3.49915     -20.31598       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='K 1O 1H 1/00         13.09556   -19.67499    -20.27047      -20.40509   '//&
            '  -6.97647      -0.10298     -12.38532        8.68236   -3.21046'
       i=i+1
       String(i)='Ca1O 1H 1/00         12.47599   -21.20812    -21.82498      -13.00859   '//&
            ' -34.30685      28.88246     -17.82603        0.00000    0.00000'
       i=i+1
       String(i)='Ca1F 2/00             9.57223   -28.08659    -27.85892      -27.99763   '//&
            ' -20.07617      28.23781     -57.31554       39.96041  -12.19525'
       i=i+1
       String(i)='Ca1Cl2/00            11.34211   -22.19594    -21.62756      -23.31291   '//&
            ' -16.48766      27.06712     -52.74009       36.78596  -11.07337'
       i=i+1
       String(i)='Ti1O 2/00            10.62104   -32.07387    -33.72678      -27.08064   '//&
            ' -18.98997      -1.11365      -8.94606        3.43842   -1.74362'
       i=i+1
       String(i)='Ti1F 2/00             9.52610   -32.09305    -35.46747      -28.32667   '//&
            ' -19.48672       1.42903     -13.08602        5.29826   -1.93708'
       i=i+1
       String(i)='Ti1Cl2/00            12.79434   -23.35985    -25.97792      -17.30143   '//&
            ' -22.05236       8.42875      -9.18446        0.00000    0.00000'
       i=i+1
       String(i)='Cr1O 2/00            12.95330   -24.87400    -24.86160      -17.56970   '//&
            ' -32.38580      32.02420     -32.10370        8.17528    0.00000'
       i=i+1
       String(i)='Fe1F 2/00            12.48504   -23.40561    -25.32780      -22.38348   '//&
            '  -8.90181      -9.82714       2.51336       -2.81621    0.00000'
       i=i+1
       String(i)='Fe1Cl2/00            13.35378   -19.50884    -21.04874      -19.27517   '//&
            '  -6.84624      -8.98069       4.79455       -5.20958    1.02666'
       i=i+1
       String(i)='Ni1Cl2/00            14.06431   -17.83550    -20.53281      -17.14119   '//&
            '  -7.58156      -3.72385      -3.15655        0.00000    0.00000'
       i=i+1
       String(i)='Cu1F 2/00            14.27701   -18.93583    -20.65558      -16.26595   '//&
            ' -12.11369       2.37546      -7.86531        1.94819   -0.44626'
       i=i+1
       String(i)='H 3O 1/10            17.00296   -40.72692    -46.37412      -35.33070   '//&
            ' -19.63690      -8.38967      -3.16264       -1.61309   -0.43336'
       i=i+1
       String(i)='H 2C 1O 1/00         19.01796   -37.43773    -42.48244      -32.82450   '//&
            ' -18.73767      -7.39374      -3.90841       -0.11372   -0.91587'
       i=i+1
       String(i)='H 1N 1C 1O 1/00      16.88890   -43.00595    -47.03093      -46.98439   '//&
            '  -1.70575     -26.78706       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='H 2N 2/00            21.89353   -29.17820    -30.44058      -36.62893   '//&
            '   6.09098     -20.96939       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='H 1N 1O 2/00         21.43684   -31.17834    -33.76627      -35.21117   '//&
            '   0.49822     -20.07551       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='H 1O 2N 1/00         21.47374   -31.12728    -33.71482      -35.15755   '//&
            '   0.45111     -20.00892       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='C 3H 1/00            19.34736   -41.90148    -23.57256      -70.23614   '//&
            '  29.53539     -56.19797      36.47223      -23.57518    5.38631'
       i=i+1
       String(i)='C 3N 1/00            24.32980   -58.11380    -41.14880      -12.64890   '//&
            ' -29.15200      45.34900     -24.57300        0.00000    0.00000'
       i=i+1
       String(i)='C 1H 3/00            20.95931   -30.56753    -34.64716      -26.47493   '//&
            ' -14.71851      -7.47864       0.06655       -2.74628    0.00000'
       i=i+1
       String(i)='C 2H 2/00            15.94051   -38.68833    -46.24242      -34.79402   '//&
            ' -22.18467      -3.34030      -8.28849        0.00000    0.00000'
       i=i+1
       String(i)='C 2H 1Cl1/00         18.62680   -37.66984    -43.21678      -33.44997   '//&
            ' -18.83205     -10.59358       2.07853       -5.88315    1.05078'
       i=i+1
       String(i)='C 4/00               17.59140   -45.69628    -51.93856      -40.70369   '//&
            ' -23.78405     -10.61553      -1.70946       -3.36065    0.00000'
       i=i+1
       String(i)='C 2F 2/00            20.00733   -37.68491    -43.31988      -33.59896   '//&
            ' -19.60588      -8.79663      -1.78625       -2.53762    0.00000'
       i=i+1
       String(i)='C 2Cl2/00            20.11666   -35.17901    -40.41618      -31.39938   '//&
            ' -17.76259     -10.05975       1.82055       -5.34588    0.93702'
       i=i+1
       String(i)='C 1F 3/00            20.94031   -34.58521    -39.47344      -30.43571   '//&
            ' -17.69545      -7.52011      -3.23485       -0.62910   -0.56787'
       i=i+1
       String(i)='C 1Cl3/00            24.24500   -24.37062    -27.70506      -21.44632   '//&
            ' -11.92859      -7.25642       1.65721       -3.91889    0.74039'
       i=i+1
       String(i)='N 1H 3/00            21.51595   -29.38598    -31.79979      -33.64444   '//&
            '   2.02775     -18.96687       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='N 1O 3/00            24.45499   -28.03194    -30.16490      -32.33383   '//&
            '   0.72423     -18.42374       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='Al1F 3/00            16.49233   -42.71688    -49.05450      -38.07831   '//&
            ' -20.56016     -11.38085      -3.07561       -0.78095   -0.87376'
       i=i+1
       String(i)='Al2O 2/00            18.77160   -37.27395    -42.42588      -34.05183   '//&
            ' -16.46030     -11.81530      -0.91341       -1.86648   -0.41254'
       i=i+1
       String(i)='Al1Cl3/00            20.50465   -30.81432    -35.32895      -27.54926   '//&
            ' -14.08157      -9.94246       0.59426       -2.71623    0.00000'
       i=i+1
       String(i)='Si1F 3/00            16.56528   -42.81660    -48.94383      -37.47877   '//&
            ' -21.64199     -10.06107      -4.54386        0.51418   -1.34295'
       i=i+1
       String(i)='Si1Cl3/00            21.34353   -29.21425    -33.26279      -25.45932   '//&
            ' -14.29567      -8.24110      -0.71302       -1.40687   -0.43144'
       i=i+1
       String(i)='P 1F 3/00            19.47558   -36.74958    -41.11066      -32.30699   '//&
            ' -21.30178      -2.24895      -9.21554        2.04615   -1.10133'
       i=i+1
       String(i)='P 4/00               22.55658   -30.20469    -30.09712      -26.36673   '//&
            ' -25.20027      13.97869     -18.37367        3.21152    0.00000'
       i=i+1
       String(i)='P 1Cl3/00            23.81167   -23.73989    -26.13894      -20.98211   '//&
            ' -10.64962     -17.93483      30.59326      -34.22365   12.13041'
       i=i+1
       String(i)='S 1O 3/00            22.29116   -34.56819    -39.00181      -30.74303   '//&
            ' -19.07821       0.27812     -18.10492       12.54103   -5.03487'
       i=i+1
       String(i)='S 4/00               24.64241   -23.00960    -27.04488      -20.22269   '//&
            ' -10.20690     -11.16804       5.11359       -3.85449    0.00000'
       i=i+1
       String(i)='Cl1F 3/00            29.31721   -12.69763    -14.43264      -10.45171   '//&
            ' -11.11223       5.38869      -5.87228        0.00000    0.00000'
       i=i+1
       String(i)='Ti1F 3/00            15.12776   -46.27428    -50.76873      -40.80837   '//&
            ' -25.90988      -4.70973     -11.19413        4.04282   -2.27440'
       i=i+1
       String(i)='Ti1Cl3/00            20.14654   -33.82196    -36.40679      -29.79907   '//&
            ' -18.99659      -3.64342      -6.56626        1.35894   -1.13233'
       i=i+1
       String(i)='Cr1O 3/00            21.65760   -35.68570    -37.73280      -27.75000   '//&
            ' -37.78440      28.98680     -32.52960        7.43559    0.00000'
       i=i+1
       String(i)='Fe1F 3/00            19.20740   -36.06418    -39.63558      -33.10142   '//&
            ' -15.26256     -11.63596      -1.44767       -0.07105   -1.25691'
       i=i+1
       String(i)='Fe1Cl3/00            22.47916   -25.51468    -27.46780      -23.78327   '//&
            '  -9.30465     -11.16694       3.34308       -3.18130    0.00000'
       i=i+1
       String(i)='H 1C 3N 1/00         22.24339   -64.45121    -47.92848      -95.56953   '//&
            '  22.67568     -46.04954       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='C 4H 1/00            23.11911   -61.82341    -46.86583      -88.55367   '//&
            '  20.84906     -58.52803      25.85646      -15.38321    2.21589'
       i=i+1
       String(i)='C 1H 4/00            28.87310   -41.19750    -47.44070      -33.58400   '//&
            ' -33.54430      19.97800     -29.95570        7.40057    0.00000'
       i=i+1
       String(i)='C 1H 3F 1/00         28.73587   -41.45924    -47.72814      -36.42000   '//&
            ' -20.77442      -8.67920      -3.34979       -0.68635   -0.82860'
       i=i+1
       String(i)='C 1H 3Cl1/00         29.43441   -38.82237    -44.69017      -34.12821   '//&
            ' -19.01459      -9.63324      -0.21402       -3.24085    0.00000'
       i=i+1
       String(i)='C 1H 2F 2/00         28.51506   -43.03210    -49.60636      -37.96844   '//&
            ' -21.73890      -9.24872      -3.66873       -0.65329   -0.91953'
       i=i+1
       String(i)='C 1H 2Cl2/00         30.43158   -36.46967    -42.04803      -32.22510   '//&
            ' -17.90951      -9.39929      -0.15681       -3.03691    0.00000'
       i=i+1
       String(i)='C 5/00               22.93193   -62.41802    -71.45335      -55.89795   '//&
            ' -31.69230     -19.08487       6.64701      -13.02862    2.98298'
       i=i+1
       String(i)='C 1F 4/00            28.92460   -47.23795    -54.59703      -42.00343   '//&
            ' -24.45608     -10.01347      -5.46064        0.10333   -1.12838'
       i=i+1
       String(i)='C 1Cl4/00            33.95584   -31.08406    -35.99329      -27.79911   '//&
            ' -15.40542      -9.42535       1.94589       -4.85877    0.88199'
       i=i+1
       String(i)='N 2O 3/00            30.07424   -39.29081    -41.66653      -47.50360   '//&
            '   4.29634     -27.36158       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='Mg1O 2H 2/00         27.00790   -40.11386    -45.47302      -37.70343   '//&
            ' -16.74654      -9.39586      -7.43707        3.55636   -2.29899'
       i=i+1
       String(i)='Si1H 4/00            31.39280   -31.66999    -36.53478      -27.72501   '//&
            ' -15.94108      -6.45007      -4.71987        2.48629   -1.90094'
       i=i+1
       String(i)='Si1H 3F 1/00         28.80534   -38.00975    -43.86159      -33.34709   '//&
            ' -19.73706      -6.19475      -8.58112        4.99228   -2.83217'
       i=i+1
       String(i)='Si1H 3Cl1/00         30.39170   -33.46920    -39.64860      -14.90570   '//&
            ' -76.06730     105.12700    -104.18900       33.90740    0.00000'
       i=i+1
       String(i)='Si1H 2F 2/00         26.62961   -44.40514    -51.25808      -39.10842   '//&
            ' -22.62684      -9.56521      -5.97844        1.95953   -1.94646'
       i=i+1
       String(i)='Si1H 2Cl2/00         29.80513   -35.14952    -40.59284      -31.09874   '//&
            ' -16.50579     -11.78565       2.00505       -3.57905    0.00000'
       i=i+1
       String(i)='Si1F 4/00            23.56070   -57.03103    -65.86803      -50.43487   '//&
            ' -29.21075     -12.91739      -6.92422        1.19279   -1.92087'
       i=i+1
       String(i)='Si1Cl4/00            30.09390   -38.25388    -44.22692      -33.85901   '//&
            ' -19.01393     -10.66721      -1.20908       -1.84547   -0.52787'
       i=i+1
       String(i)='S 5/00               35.14204   -30.62362    -34.81059      -27.67445   '//&
            ' -13.19658     -14.62682       6.38709       -4.95516    0.00000'
       i=i+1
       String(i)='Ca1O 2H 2/00         25.58137   -42.35680    -44.95006      -41.45103   '//&
            ' -26.89552      25.13195     -58.26530       38.99881  -12.22851'
       i=i+1
       String(i)='Ti1F 4/00            22.69905   -56.72157    -63.08099      -50.12254   '//&
            ' -31.52038      -6.53906     -13.19543        4.75190   -2.78048'
       i=i+1
       String(i)='Ti1Cl4/00            28.24314   -41.96032    -46.05239      -37.07742   '//&
            ' -23.20188      -5.73301      -6.77422        0.67248   -1.10180'
       i=i+1
       String(i)='Fe1O 2H 2/00         27.36818   -40.78487    -45.55325      -38.72269   '//&
            '  -3.35828     -69.75008      97.75388      -81.90154   24.52803'
       i=i+1
       String(i)='C 5H 1/00            30.96235   -69.45077    -56.96306      -95.19513   '//&
            '  14.62978     -64.08579      37.98449      -28.19977    6.35654'
       i=i+1
       String(i)='C 5N 1/00            35.19780   -79.84050    -93.96270       -0.64891   '//&
            ' -35.92700      47.18900     -25.20800        0.00000    0.00000'
       i=i+1
       String(i)='C 2H 4/00            34.44737   -56.05465    -63.57950      -48.72579   '//&
            ' -27.45675     -13.37917      -0.72887       -4.51682    0.00000'
       i=i+1
       String(i)='C 4N 2/00            25.99153   -78.28196    -86.83868      -87.86776   '//&
            '  -3.24717     -50.17531       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='N 2H 4/00            38.00271   -42.29548    -46.29684      -50.44263   '//&
            '   4.13615     -28.56528       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='N 2O 4/00            40.18022   -46.30125    -50.62507      -55.56935   '//&
            '   2.83763     -31.73237       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='S 6/00               43.41791   -37.24510    -42.33669      -34.05427   '//&
            ' -16.06755     -17.83859       7.70321       -6.02047    0.00000'
       i=i+1
       String(i)='K 2O 2H 2/00         37.03200   -43.33809    -46.23190      -45.12766   '//&
            ' -16.00407      -2.35174     -23.27795       15.81983   -6.00646'
       i=i+1
       String(i)='C 6H 1/00            34.73410   -89.37270    -80.25633     -113.51267   '//&
            '   5.94396     -66.41586      27.36873      -20.00782    3.18613'
       i=i+1
       String(i)='S 7/00               51.36072   -42.87460    -50.22174      -39.31014   '//&
            ' -19.11261     -20.70038       8.92459       -7.02453    0.00000'
       i=i+1
       String(i)='H 1C 5N 1/00         33.85704   -91.99492    -80.89653     -123.98809   '//&
            '  16.89760     -62.04005       0.00000        0.00000    0.00000'
       i=i+1
       String(i)='C 7H 1/00            41.83051   -91.18203   -109.81721      -82.24031   '//&
            ' -49.36981     -26.51185       9.00197      -19.52409    4.63153'
       i=i+1
       String(i)='C 7N 1/00            48.81290  -107.39200   -127.37300      -25.13250   '//&
            ' -36.46200      47.78900     -26.65200        0.00000    0.00000'
       i=i+1
       String(i)='S 8/00               60.82930   -49.96526    -57.26374      -46.38877   '//&
            ' -21.76996     -24.06087      10.25465       -8.08919    0.00000'
    End if
    
    dif=ichar('a')-ichar('A')
    do i = 1, 273
       do j=1, 256
          if (string(i)(j:j) .ge. 'a' .and. string(i)(j:j) .le. 'z') &
               string(i)(j:j)=char(ichar(string(i)(j:j)) - dif)
          if (string(i)(j:j) .eq. '_') string(i)(j:j)=' '
       end do
       read (string(i),FMT='(A16,5X,F8.5,2X,F10.5,3X,F10.5,5X,F10.5,3X,F10.5,4X,F10.5,4X,F10.5,6X,F9.5,1X,F9.5)')&
            molec(i),(equil(j,i),j=1,9)
    enddo
    
  end subroutine read_equil_cte
  
  !-------------------------------------------------------------------
  ! Read the elements included in the molecules
  !-------------------------------------------------------------------   
 subroutine read_elements
    Use Atomic_data 
    Use Variables
    Implicit None
    integer :: i, j
    Integer, Dimension(21) :: idx
    Logical, Save :: FirstTime=.True.

    If (FirstTime) then
       Do i = 1, 21
          idx(i)=-1
          Do j=1, N_elements
             If (Elements(i) .eq. Atom_char(j)) then
                idx(i)=j
             End if
          End do
          If (idx(i) .eq. -1) then
             Print *,'Error. Unidentified element in chemical.f90'
             Print *,elements(i), i
             Stop
          End if
       End do
    Endif
    Do i=1, 21
       Abund_atom(i)=10.**(At_abund(idx(i))-12.0)
       Pot_ion(i)=At_ioniz1(idx(i))
    End do
  end subroutine read_elements
  !-------------------------------------------------------------------
  ! Parse all the molecules with the stequiometric coefficients
  !-------------------------------------------------------------------   
  subroutine read_estequio
    Use Variables
    Implicit None
    integer :: i, j, from, step, found, found_bak, step_valencia, temp_int
    character(len=16) :: temp, temp2
    character(len=1) :: valencia
    character(len=2) :: carga
    charge = 0.d0
    do i = 1, 273
       nombre_mol(i) = ''
       temp2 = ' '
       temp = molec(i)
       found = 1
       found_bak = 1
       do j = 1, 21
          from = index(molec(i),elements(j))
          if (from /= 0) then
             
             if (temp(from+1:from+1) == ' ') then 
                step = 0
                step_valencia = 2
             else
                step = 1
                step_valencia = 2
             endif
             
             found_bak = found 
             found = found + 2
             valencia = temp(from+step_valencia:from+step_valencia)
             
             read(valencia,*) temp_int
             estequio(i,j) = temp_int
             
             if (valencia == '1') then
                valencia = ''
                found = found - 1
             endif
             temp2(found_bak:found) = temp(from:from+step)//valencia
             
          endif
       enddo
       
       from = index(temp,'/')
       read (temp(from+1:from+2),*) temp_int
       if (temp_int /= 0) then
          if (temp_int < 10) then
             charge(i) = -temp_int
          else
             charge(i) = temp_int / 10
          endif
       endif
       
       nombre_mol(i) = temp2
       
    enddo
    
  end subroutine read_estequio
  
  !-------------------------------------------------------------------
  ! Read the elements present in each molecule
  !-------------------------------------------------------------------   
  subroutine read_composition
    Use Variables
    Implicit None
    integer :: i, j, k, temp
    
    n_atoms_mol = 0.d0
    
    do i = 1, 273
       k = 1
       do j = 1, 21
          temp = index(molec(i),elements(j))
          
          if (temp /= 0) then
             composicion(i,k) = j
             k = k + 1
             n_atoms_mol(i) = n_atoms_mol(i) + estequio(i,j)
          endif
       enddo
    enddo
    
  end subroutine read_composition
  
  !-------------------------------------------------------------------   
  ! Calculates the equilibrium constants for a given temperature
  !-------------------------------------------------------------------      
  subroutine calc_equil(T)
    Use Variables
    Implicit None
    real(kind=8) :: T, temp, logar
    integer :: i, j, k
    
    Call Time_routine('calc_equil',.True.)
    logar = log10(5040.d0 / T)
    do j = 1, n_included
       k=which_included(j)
       temp = 0.d0
       do i = 0, 8
          temp = temp + equil(i+1,k) * (logar)**i
       enddo
       
       equilibrium(j) = 10.d0**temp
       
    enddo
    
    ! Transform the units from SI to cgs multipliying by 10 the necessary times depending on the
    ! units of the equilibrium constant
    equilibrium = equilibrium * 10.d0 ** (n_atoms_mol - 1.d0)
    Call Time_routine('calc_equil',.False.)
    
  end subroutine calc_equil
  
  !-------------------------------------------------------------------
  ! Read the equilibrium constants for the atomic and ionic species
  !-------------------------------------------------------------------
  subroutine read_partition_cte_atomic
    Use Variables
    Implicit None
    integer :: i, j, codigo, cod_specie, carga
    real(kind=8) :: data(7)
    character (len=256), Dimension(59) :: string
    Data String/'      10     0.301030 -1.00000e-05      0.00000      0.00000      0.00000      0.00000      0.00000',&
         '      11      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000',&
         '      12      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000',&
         '      20      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000',&
         '      21     0.301030      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000',&
         '      30     0.967520   -0.0945200    0.0805500      0.00000      0.00000      0.00000      0.00000',&
         '      31     0.772390   -0.0254000      0.00000      0.00000      0.00000      0.00000      0.00000',&
         '      32     0.661580    -0.359020     0.632060     0.160910     -1.60592      1.60171    -0.482600',&
         '      40     0.606830   -0.0867400     0.305650    -0.281140      0.00000      0.00000      0.00000',&
         '      41     0.949680   -0.0646300   -0.0129100      0.00000      0.00000      0.00000      0.00000',&
         '      42     0.961510   -0.0864300     0.173860    -0.103300    -0.265220     0.408560    -0.172010',&
         '      50     0.950330   -0.0570300      0.00000      0.00000      0.00000      0.00000      0.00000',&
         '      51     0.604050   -0.0302500    0.0452500      0.00000      0.00000      0.00000      0.00000',&
         '      52     0.770960   -0.0162900   -0.0181700   -0.0126800  -0.00567000  -0.00519000   0.00353000',&
         '      60     0.762840   -0.0358200   -0.0561900      0.00000      0.00000      0.00000      0.00000',&
         '      61     0.934710   -0.0542700  0.000960000    -0.154690     0.136560   -0.0868400    0.0275300',&
         '      62      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000',&
         '      70     0.309550    -0.177780      1.10594     -2.42847      1.70721      0.00000      0.00000',&
         '      71      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000',&
         '      72      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000',&
         '      80   0.00556000    -0.128400     0.815060     -1.73635      1.26292      0.00000      0.00000',&
         '      81     0.302570  -0.00451000      0.00000      0.00000      0.00000      0.00000      0.00000',&
         '      90     0.767860   -0.0520700     0.147130    -0.213760      0.00000      0.00000      0.00000',&
         '      91   0.00334000  -0.00995000      0.00000      0.00000      0.00000      0.00000      0.00000',&
         '      92      1.04920    -0.170440   -0.0944400    0.0672900     0.186100    -0.106680   -0.0417000',&
         '     100     0.978960    -0.192080    0.0475300      0.00000      0.00000      0.00000      0.00000',&
         '     101     0.756470   -0.0549000    -0.101260      0.00000      0.00000      0.00000      0.00000',&
         '     102     0.750660    -0.627890     0.509890     0.983780     -1.35593    -0.273830     0.641920',&
         '     110     0.646180    -0.311320     0.686330    -0.475050      0.00000      0.00000      0.00000',&
         '     111     0.935880    -0.188480    0.0892100    -0.224470      0.00000      0.00000      0.00000',&
         '     112     0.979040    -0.176100     0.122120     0.126960    -0.269110   -0.0183100     0.100210',&
         '     120     0.952540    -0.151660    0.0234000      0.00000      0.00000      0.00000      0.00000',&
         '     121     0.619710    -0.174650     0.482830    -0.391570      0.00000      0.00000      0.00000',&
         '     122     0.759070   -0.0418900   -0.0436400   -0.0259300  -0.00738000  -0.00353000    0.0168400',&
         '     130     0.744650   -0.0738900   -0.0696500      0.00000      0.00000      0.00000      0.00000',&
         '     131     0.927280    -0.159130   -0.0198300      0.00000      0.00000      0.00000      0.00000',&
         '     132      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000',&
         '     140     0.344190    -0.481570      1.92563     -3.17826      1.83211      0.00000      0.00000',&
         '     141      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000',&
         '     142      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000',&
         '     150    0.0746000    -0.757590      2.58494     -3.53170      1.65240      0.00000      0.00000',&
         '     151     0.343830    -0.368520      1.08426    -0.848490     -1.57275      3.15963     -1.51923',&
         '     160      1.47343    -0.972200      1.47986    -0.932750      0.00000      0.00000      0.00000',&
         '     161      1.41964   -0.0625300   -0.0702400   -0.0497800   -0.0230200   -0.0210400    0.0121100',&
         '     162      1.42634   -0.0474700   -0.0536800   -0.0389300   -0.0192200   -0.0143200   0.00491000',&
         '     170      1.02332     -1.02540      2.02181     -1.32723      0.00000      0.00000      0.00000',&
         '     171     0.870480   -0.0653200   -0.0534900   -0.0173700    0.0900500    0.0808300   -0.0406500',&
         '     172     0.778150      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000',&
         '     180     0.808100    -0.391080      1.74756     -3.13517      1.93514      0.00000      0.00000',&
         '     181     0.874240    -0.202180     0.477170    -0.234360    -0.755890      1.19515    -0.513990',&
         '     190      1.44701    -0.670400      1.01267    -0.814280      0.00000      0.00000      0.00000',&
         '     191      1.42759    -0.109300    -0.115070   -0.0696300   -0.0213000   -0.0146600    0.0493400',&
         '     192      1.38556    -0.133840    -0.135030   -0.0765500   -0.0242400    0.0354200    0.0383900',&
         '     200      1.49063    -0.336620    0.0855300    -0.192770      0.00000      0.00000      0.00000',&
         '     201     0.935940    -0.127640    -0.101920   -0.0305000    0.0253100     0.202280    -0.120080',&
         '     202     0.930850    -0.135770    -0.104080   -0.0226000    0.0437300     0.209660    -0.140380',&
         '     210     0.368840    -0.467400      1.02157     0.708720      0.00000      0.00000      0.00000',&
         '     211    0.0116100    -0.186610      1.04001     -2.40338      2.08988    0.0193500    -0.605840',&
         '     212      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000      0.00000'/
    
    
    atomic_partition = 0.d0
    do i = 1, 59
       read (String(i),*) codigo, (data(j),j=1,7)
       cod_specie = codigo / 10
       carga = codigo - cod_specie * 10
       atomic_partition(:,carga+1,cod_specie) = data
    enddo
    
    
    
  end subroutine read_partition_cte_atomic
  
  !-------------------------------------------------------------------   
  ! Calculates the atomic equilibrium constants for a given temperature
  !-------------------------------------------------------------------      
  subroutine calc_equil_atomic(T)
    Use Variables
    Implicit None
    real(kind=8) :: T, temp, logar, phi(3)
    integer :: i, j, k, l
    
    logar = log10(5040.d0 / T)
    
    ! All the species
    do l = 1, 21
       
       ! Calculate the partition function of the neutral, + and - ion of the species         
       do k = 1, 3
          temp = 0.d0
          do i = 0, 6
             temp = temp + atomic_partition(i+1,k,l) * (logar)**i
          enddo
          phi(k) = 10.d0**temp
       enddo
       
       ! Positive ion constant
       equilibrium_atomic(1,l) = 3.41405d0 + NA_ME + 2.5d0 * log10(T) - 5039.9d0 * pot_ion(l) / T + &
            log10( 2.d0*phi(2)/phi(1) )
       
       
       equilibrium_atomic(1,l) = 10.d0**(equilibrium_atomic(1,l))
       
       ! Negative ion constant         
       equilibrium_atomic(2,l) = 3.41405d0 + NA_ME + 2.5d0 * log10(T) - 5039.9d0 * afinidad(l) / T + &
            log10( 2.d0*phi(1)/phi(3) )
       equilibrium_atomic(2,l) = 10.d0**(equilibrium_atomic(2,l))
       
    enddo
    
    ! Transform the units from N/m^2 to dyn/cm^2
    equilibrium_atomic = equilibrium_atomic * 10.d0
    
  end subroutine calc_equil_atomic
  
  !-------------------------------------------------------------------   
  ! Read what species are going to be included
  !-------------------------------------------------------------------         
  subroutine read_what_species
    Use Variables
    Implicit None
    integer :: i, j
    character(len=16) :: name
    Character (len=16), Dimension(:), Allocatable :: names
    
    If (eqstate_switch_others .eq. 2) then 
       n_included=273
       If (.not. Allocated(names)) Allocate(names(n_included))
       names=molec
    Else
       n_included=2
       If (.not. Allocated(names)) Allocate(names(n_included))
       names=(/'H 2/00','H 2/10'/)
    End if

    includ = 0
    If (.not. Allocated(which_included)) allocate (which_included(n_included))
    
    do i = 1, n_included
       name=names(i)
       do j = 1, 273
          if (molec(j) == name) then
             includ(j) = 1
             which_included(i) = j
          endif
       enddo
    enddo
    
  end subroutine read_what_species
  
  !-----------------------------------------------------------------
  ! Calculates the abundance of a given molecule in chemical equilibrium
  ! INPUT :
  !   mol_code : integer to identify the molecule (see file TE_data/equil_cte.dat)
  !   n_grid : number of grid points in the T, nH and ne arrays
  !   height_in : vector of heights (it is used for nothing indeed)
  !   temper_in : array of temperatures in K
  !  PT_in : array of total pressure in dyn*cm^2
  !  abundance_file : file in which the molecular abundances will be saved
  ! OUTPUT : 
  !  PH_out : partial pressure of H atoms (dyn/cm^2)
  !  PHminus_out : partial pressure of H- atoms (dyn/cm^2)
  !  PHplus_out : partial pressure of H+ atoms (dyn/cm^2)
  !  PH2_out : partial pressure of H2 molecules (dyn/cm^2)
  !  PH2plus_out : partial pressure of H2+ molecules (dyn/cm^2)
  !-----------------------------------------------------------------
  function calculate_abundance(mol_code, n_grid, height_in, temper_in, PT_in, &
       abundance_file, PH_out, PHminus_out, PHplus_out, PH2_out, PH2plus_out, P_elec_arr)
    Use Variables
    Implicit None
    integer :: n_grid, mol_code
    real(kind=8) :: height_in(n_grid), temper_in(n_grid), PT_in(n_grid), n_e_in(n_grid)
    real(kind=8) :: calculate_abundance(n_grid), abun_out(n_grid)
    real(kind=8), dimension(n_grid) :: PH_out, PHminus_out, PHplus_out, PH2_out, PH2plus_out, P_elec_arr
    character(len=40) :: abundance_file
    real(kind=8) :: mole(273), height, minim_ioniz
    integer :: i, ind, l, loop, minim
    
    ! Reading equilibrium constants of the 273 molecules included
    call read_equil_cte
    ! Reading equilibrium constants of atomic and ionic species
    call read_partition_cte_atomic
    ! Reading 21 elements
    call read_elements
    ! Reading estequiometer values
    call read_estequio
    ! Reading composition of the 273 molecules
    call read_composition
    ! Reading what molecules are included
    call read_what_species
    
    do loop = 1, n_grid
       
       height = height_in(loop)
       temper = temper_in(loop)
       P_total = PT_in(loop)
       
       ! Calculating molecular equilibrium constants
       call calc_equil(temper)
       ! Calculating ionic equilibrium constants
       call calc_equil_atomic(temper)
       
       ! Initial conditions
       ! Initialize assuming that the total gas pressure is given by H
       x_sol = 1.d0
       x0_sol = 1.d0
       x_sol(1:21) = P_total * abund_atom
       x0_sol(1:21) = x_sol(1:21)
       
       !       call mnewt(100,x_sol,22,1.d-4,1.d-4)
       
       P_elec_arr(loop) = x_sol(22)
       
       mole = 1.d0
       i = mol_code
       minim = 0
       minim_ioniz = 100.d0
       do l = 1, 4
          ind = composicion(i,l)
          if (ind /= 0.d0) then
             if (pot_ion(ind) < minim_ioniz) then
                minim = ind
                minim_ioniz = pot_ion(ind)
             endif
             mole(i) = mole(i) * x_sol(ind)**estequio(i,ind)
          endif
       enddo
       if (equilibrium(i) == 0.d0) then
          mole(i) = 0.d0
       else
          if (charge(i) == 1) then
             P_elec = n_e * PK_CH * temper
             mole(i) = (mole(i) / (equilibrium(i) * P_elec_arr(loop)) * &
                  equilibrium_atomic(1,minim)) / (PK_CH * temper)
          else
             mole(i) = (mole(i) / equilibrium(i)) / (PK_CH * temper)
          endif
       endif
       
       if (.not.(mole(i)>0) .and. .not.(mole(i)<=0) ) mole(i) = 0.d0
       write(45,*) height, mole(i)
       abun_out(loop) = mole(i)
       
       ! Now extract also the partial pressure from H, H-, H+, H2 and H2+   
       
       PH_out(loop) = x_sol(1)
       PHminus_out(loop) = x_sol(1) * P_elec_arr(loop) / equilibrium_atomic(2,1)
       PHplus_out(loop) = x_sol(1) / P_elec_arr(loop) * equilibrium_atomic(1,1)
       if (temper < 1.d5) then
          PH2_out(loop) = x_sol(1)**2 / equilibrium(1)
          PH2plus_out(loop) = x_sol(1)**2 / P_elec_arr(loop) * (equilibrium_atomic(1,1) / equilibrium(2))
       else
          PH2_out(loop) = 0.d0
          PH2plus_out(loop) = 0.d0
       endif
       
    enddo
    
    calculate_abundance = abun_out
    
    
  end function calculate_abundance


!-----------------------------------------------------------------
! Calculates the abundance of a given molecule in chemical equilibrium
! INPUT :
!	mol_code : integer to identify the molecule (see file TE_data/equil_cte.dat)
!	n_grid : number of grid points in the T, nH and ne arrays
!	height_in : vector of heights (it is used for nothing indeed)
!	temper_in : array of temperatures in K
!  PT_in : array of total pressure in dyn*cm^2
!  abundance_file : file in which the molecular abundances will be saved
! OUTPUT :
!  PH_out : partial pressure of H atoms (dyn/cm^2)
!  PHminus_out : partial pressure of H- atoms (dyn/cm^2)
!  PHplus_out : partial pressure of H+ atoms (dyn/cm^2)
!  PH2_out : partial pressure of H2 molecules (dyn/cm^2)
!  PH2plus_out : partial pressure of H2+ molecules (dyn/cm^2)
!-----------------------------------------------------------------
  Subroutine compute_others_from_T_Pe_Pg(n_grid, temp4, Pe4, Pg4,&
       nH4, nHminus4, nHplus4, nH24, nH2plus4)
    Use Debug_module
    Use Variables
    Use Atomic_data
    Use LTE
    Use HatomicfromPe
    Implicit None
    integer :: n_grid
    real , dimension(n_grid) :: temp4, Pg4, PH4, PHminus4,PHplus4, PH24, &
         PH2plus4, Pe4, try_Pe4
    real , dimension(n_grid) :: nH4, nHminus4,nHplus4, nH24, &
         nH2plus4, ne4
    real(kind=8) :: temper_in(n_grid), Pe_in(n_grid), n_e_in(n_grid), Pt_in(n_grid)
    real(kind=8), dimension(n_grid) :: PH_out, PHminus_out, PHplus_out, PH2_out, PH2plus_out
    real(kind=8) :: mole(273), minim_ioniz
    real(kind=8), dimension(22), save :: initial_values
    Real :: logPe, T, AtomicFraction, Ne, Ptot, NHtot, Met2, DU1, DU2, DU3
    Real :: nHmolec, Ioniz, HLimit, n2p
    Real, Dimension(n_grid) :: n0overn, n1overn, n2overn
    Real, Dimension(1) :: T1, Ne1
    integer :: i, ind, l, loop , minim, niters, iter, iel
    Logical, Save :: FirstTime=.True.
    Logical :: Warning=.False.
    Real, Parameter :: Precision=1e-4
    Integer, Parameter :: Maxniters=100
    Character (Len=256) :: String

    Call Time_routine('compute_others_from_T_Pe_Pg',.True.)

    If (eqstate_switch_others .eq. 3) then ! Use Wittmann's
       Call Wittmann_compute_others_from_T_pe_pg(n_grid, temp4, Pe4, Pg4,&
       nH4, nHminus4, nHplus4, nH24, nH2plus4)
       Call Time_routine('compute_others_from_T_Pe_Pg',.False.)
       Return
    Endif
    
    HLimit=1.-10**(At_abund(2)-At_abund(1))
    If (eqstate_switch_others .eq. 0) then ! Use ANN 
       Ne4(1:n_grid)=Pe4(1:n_grid)/BK/Temp4(1:n_grid)
       Call Saha123(n_grid, 1, Temp4, Ne4, n0overn, n1overn, n2overn)
       Met2=At_abund(26)-7.5 ! Metalicity
       If (Met2 .gt. .5) then
          Debug_warningflags(flag_computeopac)=1
          Call Debug_Log('Metalicity .gt. 0.5. Clipping it',2)
          Met2=.5
       End if
       If (Met2 .lt. -1.5) then
          Debug_warningflags(flag_computeopac)=1
          Call Debug_Log('Metalicity .lt. -1.5. Clipping it',2)
          Met2=-1.5
       End if
       Do loop = 1, n_grid
          LogPe=log10(Pe4(loop))
          If (LogPe .gt. 4) then
             Debug_warningflags(flag_computeopac)=1
             Call Debug_Log('Log10 (Pe) .gt. 4. Clipping it',2)
             LogPe=4
          End if
          If (LogPe .lt. -3) then
             Debug_warningflags(flag_computeopac)=1
             Call Debug_Log('Log10 (Pe) .lt. -3. Clipping it',2)
             LogPe=-3
          End if
          T=Temp4(loop)
          If (T .lt. 1500) then
             Debug_warningflags(flag_computeopac)=1
             Call Debug_Log('T .lt. 1500. Clipping it',2)
             T=1500
          End if
          PTot=Pg4(loop)-Pe4(loop)
          nHtot=PTot*Hlimit/BK/T
          AtomicFraction=-1
          ! First check if we're in trivial T-Pe zone where all H is atomic
          If (LogPe .gt. 1.5) then ! Pe too high
             AtomicFraction=1.
          Else If (T .gt. 5800) then ! T > 5800
             AtomicFraction=1.
          Else 
             If (T .gt. 3700) then ! 3700 < T < 5800
                If (LogPe .gt. (T+3500.)/2000.*1.5-5.3 .or. &
                     LogPe .lt. (T+3500.)/2000.*3.-12.3 ) AtomicFraction=1.
             Else ! T < 3700
                If (LogPe .gt. (T+3500.)/2000.*1.5-5.3 .or. &
                     LogPe .lt. (T+3500.)/2000.*7.5-28.5 ) AtomicFraction=1.
             End if
          End if
          If (AtomicFraction .lt. -0.10) then ! Need to use ANN
             inputs(1)=(T-xmean(1))/xnorm(1)
             inputs(2)=(LogPe-xmean(2))/xnorm(2)
             inputs(3)=(Met2-xmean(3))/xnorm(3)
             
             Call ANN_Forward(W, Beta, Nonlin, inputs, outputs, nlayers, &
                  nmaxperlayer, nperlayer, ninputs, noutputs, y)
             
             AtomicFraction=outputs(1)*ynorm(1)+ymean(1)
             AtomicFraction=Max(AtomicFraction,0.)
             AtomicFraction=Min(AtomicFraction,HLimit)
             AtomicFraction=AtomicFraction/HLimit ! Renormalize to 0-1 range
          End if
          nH4(loop)=nHTot*AtomicFraction*n0overn(loop)
          nHplus4(loop)=nHTot*AtomicFraction*n1overn(loop)
          nHminus4(loop)=nHTot*AtomicFraction*n2overn(loop)
          ! Molecular Hydrogen
          nHmolec=nHTot*(1.-AtomicFraction)
          ! Set all molecular H to H2 (neglect H2+)
          nH24(loop)=nHmolec
          nH2plus4(loop)=0.
       End do
       Call Time_routine('compute_others_from_T_Pe_Pg',.False.)
       Return
    End if ! End use ANN
    
    If (eqstate_switch_others .eq. 1 .or. eqstate_switch_others .eq. 2) then ! Use Andres
! Do the actual calculation
       temper_in=temp4
       Pe_in=Pe4
       Pt_in=Pg4
       Debug_errorflags(flag_computepg)=0
       Debug_warningflags(flag_computepg)=0
       
       Do loop = 1, n_grid
          If (Pe_in(loop) .lt. Min_Pe) then
             Pe_in(loop)=Min_Pe
             Call Debug_Log('Pe .lt. Min_Pe in Compute_others_from_T_Pe_Pg', 2)
          End if
          If (Pe_in(loop) .gt. Max_Pe) then
             Pe_in(loop)=Max_Pe
             Call Debug_Log('Pe .gt. Max_Pe in Compute_others_from_T_Pe_Pg', 2)
          End if
          If (Pt_in(loop) .lt. Min_Pg) then
             Pt_in(loop)=Min_Pe
             Call Debug_Log('Pg .lt. Min_Pg in Compute_others_from_T_Pe_Pg', 2)
          End if
          If (Pt_in(loop) .gt. Max_Pg) then
             Pt_in(loop)=Max_Pg
             Call Debug_Log('Pg .gt. Max_Pg in Compute_others_from_T_Pe_Pg', 2)
          End if
       End do

       ! Reading 21 elements
       call read_elements
       If (FirstTime) then
          ! Reading equilibrium constants of the 273 molecules included
          call read_equil_cte
          ! Reading equilibrium constants of atomic and ionic species
          call read_partition_cte_atomic
          ! Reading estequiometer values
          call read_estequio
          ! Reading composition of the 273 molecules
          call read_composition
          ! Reading what molecules are included
          call read_what_species
          FirstTime=.False.
       End if
       
       do loop = 1, n_grid
          ! Initial conditions
          ! Initialize assuming that the total gas pressure is given by H
          !       x_sol(1:21) = Pe_in(1) * abund_atom* 1.d1
          x_sol(1:21)=1d-3
          initial_values = x_sol
          
          
          temper = temper_in(loop)
          P_elec = Pe_in(loop)
          P_total = Pt_in(loop)
          
          ! Calculating molecular equilibrium constants
          ! 			call calc_equil(temper)
          call calc_equil(temper)
          ! Calculating ionic equilibrium constants
          call calc_equil_atomic(temper)
          
          ! Initial conditions
          ! Initialize assuming that the total gas pressure is given by H
          x_sol(1:21) = 1.d-3
          
          niters=Maxniters
          call mnewt(3,niters,x_sol(1:21),21,1.e-5,1.e-5)
          
          iter=1
          do while ( (minval(x_sol(1:21)) < 0.d0 .or. niters .eq. Maxniters) .and. iter .le. 100)
             !       do while ( (minval(x_sol(1:21)) < 0.d0 .or. niters .eq. Maxniters) .and. iter .lt. 15)
             iter=iter+1
             Write (String,*) 'ipoint, T, Pe, Pg=',loop,temper, P_elec, P_total
             Debug_warningflags(flag_computeothers)=1
             Call Debug_Log('Solving compute_others_from_T_Pe_Pg again, '//String, 2)
             if (iter .eq. 1) then
                x_sol(1:21) = PT_in(loop) * abund_atom*.9
                x_sol(21)=PT_in(loop)*.01
             else if (iter .lt. 4) then
                x_sol = initial_values / (10**iter)
             else if (iter .lt. 7) then
                x_sol = initial_values * (10**iter)
             else if (iter .lt. 0) then
                x_sol(1)=PT_in(loop)
                Do i=2,21
                   x_sol(i)=0.
                End do
             else
                do i=1,21
                   Call Random_number(x_sol(i))
                   x_sol(i)=10**(7.*(x_sol(i)-.5))
                end do
             end if
             
             niters=Maxniters
             call mnewt(3,niters,x_sol(1:21),21,1.e-5,1.e-5)
             If (iter .ge. 10) then
                Write (String,*) 'ipoint, T, Pe, Pg, PH=',loop,temper, P_elec, P_total,x_sol(1)
                Debug_errorflags(flag_computeothers)=1
                Call Debug_Log('In Compute_others_from_T_Pg, reached max iters. Taking the following PH: '//String, 2)
                Warning=.True.
             End if
             
          enddo
          
          if (x_sol(1) .lt. 0) x_sol(1)=PT_in(loop)
          
          PH_out(loop) = x_sol(1)
          PHminus_out(loop) = x_sol(1) * Pe_in(loop) / equilibrium_atomic(2,1)
          PHplus_out(loop) = x_sol(1) / Pe_in(loop) * equilibrium_atomic(1,1)
          if (temper < 1.d5) then
             PH2_out(loop) = x_sol(1)**2 / equilibrium(1)
             PH2plus_out(loop) = x_sol(1)**2 / Pe_in(loop) * (equilibrium_atomic(1,1) / equilibrium(2))
          else
             PH2_out(loop) = 0.d0
             PH2plus_out(loop) = 0.d0
          endif
                 enddo
       nH4=PH_out/BK/Temp4
       nHminus4=PHminus_out/BK/Temp4
       nHplus4=PHplus_out/BK/Temp4
       nH24=PH2_out/BK/Temp4
       nH2plus4=PH2plus_out/BK/Temp4
       ne4=Pe_in/BK/Temp4
       Call Time_routine('compute_others_from_T_Pe_Pg',.False.)
       Return
    End if


    Call Time_routine('compute_others_from_T_Pe_Pg',.False.)

  End Subroutine compute_others_from_T_Pe_Pg
  
  
  !
  !-----------------------------------------------------------------
  ! Calculates the electron pressure and other contributors from T and Pg
  !   n_grid : number of grid points in the T, nH and ne arrays
  !   temper_in : array of temperatures in K
  !  PT_in : array of total pressure in dyn*cm^2
  ! OUTPUT : 
  !  PH_out : partial pressure of H atoms (dyn/cm^2)
  !  PHminus_out : partial pressure of H- atoms (dyn/cm^2)
  !  PHplus_out : partial pressure of H+ atoms (dyn/cm^2)
  !  PH2_out : partial pressure of H2 molecules (dyn/cm^2)
  !  PH2plus_out : partial pressure of H2+ molecules (dyn/cm^2)
  !-----------------------------------------------------------------
  Subroutine Compute_Pe(n_grid, temp4, PT4, Pe4)
    Use Debug_module
    Use Variables
    Use Atomic_data
    Use LTE
    Implicit None
    integer :: n_grid, mol_code
    real , dimension(n_grid) :: temp4, PT4, PH4, PHminus4,PHplus4, PH24, &
         PH2plus4, Pe4, T4, Pg4
    real(kind=8) :: temper_in(n_grid), PT_in(n_grid), n_e_in(n_grid)
    real(kind=8) :: calculate_abundance(n_grid), abun_out(n_grid)
    real(kind=8), dimension(n_grid) :: PH_out, PHminus_out, PHplus_out, PH2_out, PH2plus_out, P_elec_arr
    real(kind=8) :: mole(273), minim_ioniz
    real(kind=8), dimension(22), save :: initial_values
    integer :: i, ind, l, loop, minim, iter, niters, dir
    logical, Save :: FirstTime=.True.
    Real :: metalicity, Pgold, Peold, Diff1, Diff2
    Real(Kind=8) :: TotAbund, scale
    Real, Dimension(1) :: U12, U23, U1, U2, U3, DU1, DU2, DU3, Ne, P4
    Character (Len=256) :: String
    
    Call Time_routine('compute_pe',.True.)

    if (eqstate_switch .lt. 0 .or. eqstate_switch .gt. 2) then
       print *,'Unknown value for Eq state in compute_pe, eq_state.f90'
       stop
    end if

    temper_in=temp4
    PT_in=PT4
    Debug_errorflags(flag_computepe)=0
    Debug_warningflags(flag_computepe)=0

    If (eqstate_switch .eq. 0 .or. eqstate_switch .eq. 1) then ! Use ANNs only
       metalicity=At_abund(26)-7.5
       T4=temper_in
       Pg4=Pt_in
       Do loop = 1, n_grid
          Call ann_pefrompg(T4(loop), Pg4(loop), metalicity, Pe4(loop))
       End do
    End if

    If (eqstate_switch .eq. 2) then ! Use Wittmann's EoS
       Call wittmann_compute_pe(n_grid, temp4, PT4, Pe4)
       Call Time_routine('compute_pe',.False.)
       Return
    End if

    !
    ! JdlCR: Changed the convergence scheme to a more efficient one
    ! although perhaps this could be furhter improved...
    !
    If (eqstate_pe_consistency .lt. 10) then
       ! Use Pe as initial guess and iterate
       Do loop = 1, n_grid
          Pgold=1e15
          Peold=1e15
          Call Compute_Pg(1, T4(loop), Pe4(loop), Pg4(loop))

          niters=0

          ! Init direction of the correction and scale factor for Pe
          dir = 0       
          scale = 2.0d0
          
          Diff1=abs(Pt_in(loop) - Pg4(loop))/Pt_in(loop)
          Do While (  abs(Diff1) .gt. eqstate_pe_consistency .and. niters .lt. 50)
             Pgold=Pg4(loop)
             Peold=Pe4(loop)

             !
             ! Check direction for the correction and correct Pe
             ! If there is a change in the direction, it means that we are
             ! overshooting, then scale down the correction.
             !
             if(Diff1 .gt.  eqstate_pe_consistency) then
                if(dir .ne. 1) scale = sqrt(scale)
                Pe4(loop) = Pe4(loop) * scale
                dir = 1
             else if(-Diff1 .gt. eqstate_pe_consistency) then
                if(dir .ne. -1) scale = sqrt(scale)
                Pe4(loop) = Pe4(loop) / scale
                dir = -1
             end if

             ! Recompute Pg
             Call Compute_Pg(1, T4(loop), Pe4(loop), Pg4(loop))
             niters=niters+1

             ! Check Difference with the input Pgas
             Diff1=(Pt_in(loop) - Pg4(loop))/(Pg4(loop)+Pt_in(loop))
          End do
       End do
    End if
    
    Call Time_routine('compute_pe',.False.)
    Return
    
    
  End Subroutine Compute_Pe
  
  !-----------------------------------------------------------------
  ! Calculates the gas pressure and other contributors from T and Pe
  ! INPUT :
  !   n_grid : number of grid points in the T, nH and ne arrays
  !   temper_in : array of temperatures in K
  !  PT_in : array of total pressure in dyn*cm^2
  ! OUTPUT : 
  !  PH_out : partial pressure of H atoms (dyn/cm^2)
  !  PHminus_out : partial pressure of H- atoms (dyn/cm^2)
  !  PHplus_out : partial pressure of H+ atoms (dyn/cm^2)
  !  PH2_out : partial pressure of H2 molecules (dyn/cm^2)
  !  PH2plus_out : partial pressure of H2+ molecules (dyn/cm^2)
  !-----------------------------------------------------------------
  Subroutine Compute_Pg(n_grid, temp4, Pe4, Pg4)
    Use Debug_module
    Use Variables
    Use Atomic_data
    Use HatomicfromPe
    Use LTE
    Implicit None
    integer :: n_grid, mol_code
    real , dimension(n_grid) :: temp4, Pg4, PH4, PHminus4,PHplus4, PH24, &
         PH2plus4, Pe4, try_Pe4, T4, P4
    real(kind=8) :: temper_in(n_grid), Pg(n_grid), Pe_in(n_grid)
    real(kind=8) :: calculate_abundance(n_grid), abun_out(n_grid)
    real(kind=8), dimension(n_grid) :: PH_out, PHminus_out, PHplus_out, PH2_out, PH2plus_out
    real(kind=8) :: mole(273), minim_ioniz
    real(kind=8), dimension(22), save :: initial_values
    integer :: i, ind, l, loop, minim, iter, niters, iel
    Logical, Save :: FirstTime=.True.
    Real :: metalicity, HLimit, AtomicFraction, LogPe, Met2, T
    Real :: totalnuclei, donornuclei, Ioniz, Ne, scale
    Real, Dimension(1) :: n0overn, n1overn, n2overn, nminusovern, T1, Ne1
    Real(Kind=8) :: TotAbund
!    Real(Kind=8), Parameter :: BK = 1.38066D-16, Precision=1e-4
    Real(Kind=8), Parameter :: Precision=1e-4
    Character (Len=256) :: String
    Integer, Parameter :: Maxniters=1
    
    Call Time_routine('compute_pg',.True.)

    HLimit=1.-10**(At_abund(2)-At_abund(1))
    temper_in=temp4
    Pe_in=Pe4
    Debug_errorflags(flag_computepg)=0
    Debug_warningflags(flag_computepg)=0

    If (eqstate_switch .eq. 0) then ! Use NICOLE approach (with ANNs and elements)
       Met2=At_abund(26)-7.5 ! Metalicity
       If (Met2 .gt. .5) then
          Debug_warningflags(flag_computeopac)=1
          Call Debug_Log('Metalicity .gt. 0.5. Clipping it',2)
          Met2=.5
       End if
       If (Met2 .lt. -1.5) then
          Debug_warningflags(flag_computeopac)=1
          Call Debug_Log('Metalicity .lt. -1.5. Clipping it',2)
          Met2=-1.5
       End if
       Do loop=1, n_grid
          T=temp4(loop)
          totalnuclei=0.
          donornuclei=0.
          ! Start adding contributions from H (atomic only)
          If (T .lt. 1500) then
             Debug_warningflags(flag_computeopac)=1
             Call Debug_Log('T .lt. 1500. Clipping it',2)
             T=1500
          End if
          LogPe=Log10(Pe4(loop))
          Ne=Pe4(loop)/BK/T
          AtomicFraction=-1
          ! First check if we're in trivial T-Pe zone where all H is atomic
          If (LogPe .gt. 1.5) then ! Pe too high
             AtomicFraction=HLimit
          Else If (T .gt. 5800) then ! T > 5800
             AtomicFraction=HLimit
          Else 
             If (T .gt. 3700) then ! 3700 < T < 5800
                If (LogPe .gt. (T+3500.)/2000.*1.5-5.3 .or. &
                     LogPe .lt. (T+3500.)/2000.*3.-12.3 ) AtomicFraction=HLimit
             Else ! T < 3700
                If (LogPe .gt. (T+3500.)/2000.*1.5-5.3 .or. &
                     LogPe .lt. (T+3500.)/2000.*7.5-28.5 ) AtomicFraction=HLimit
             End if
          End if
          If (AtomicFraction .lt. -0.10) then ! Need to use ANN
             inputs(1)=(T-xmean(1))/xnorm(1)
             inputs(2)=(LogPe-xmean(2))/xnorm(2)
             inputs(3)=(Met2-xmean(3))/xnorm(3)
             
             Call ANN_Forward(W, Beta, Nonlin, inputs, outputs, nlayers, &
                  nmaxperlayer, nperlayer, ninputs, noutputs, y)
             
             AtomicFraction=outputs(1)*ynorm(1)+ymean(1)
             AtomicFraction=Max(AtomicFraction,0.)
             AtomicFraction=Min(AtomicFraction,HLimit)
          End if
          T1(1)=T
          Ne1(1)=Ne
          iel=1 ! Saha for atomic H
          Call Saha123(1, iel, T1(1), Ne1(1),n0overn(1),n1overn(1),n2overn(1))
          totalnuclei=totalnuclei+AtomicFraction*n0overn(1) ! P(H)/(Pg-Pe)
          totalnuclei=totalnuclei+AtomicFraction*n1overn(1) ! P(H+)/(Pg-Pe)
          totalnuclei=totalnuclei+AtomicFraction*n2overn(1) ! P(H-)/(Pg-Pe)
          totalnuclei=totalnuclei+(HLimit-AtomicFraction) ! P(H2, neglect H2+)
          donornuclei=donornuclei+AtomicFraction*n1overn(1) ! P(H+)/(Pg-Pe)
          donornuclei=donornuclei-AtomicFraction*n2overn(1) ! P(H-)/(Pg-Pe)
          Do iel=2, n_elements ! For other elements (neglect molecules)
             scale=10**(at_abund(iel)-12) ! Scale to H
             if (scale .gt. 1e-6) then ! Consider only significant elements
                Call Saha123(1, iel, T1(1), Ne1(1),n0overn(1),n1overn(1),n2overn(1))
                totalnuclei=totalnuclei+scale*n0overn(1) ! P(Fe)/(Pg-Pe)
                totalnuclei=totalnuclei+scale*n1overn(1) ! P(Fe+)/(Pg-Pe)
                totalnuclei=totalnuclei+scale*n2overn(1) ! P(Fe++)/(Pg-Pe)
                donornuclei=donornuclei+scale*n1overn(1) ! P(Fe+)/(Pg-Pe)
                donornuclei=donornuclei+2.*scale*n2overn(1) ! P(Fe++)/(Pg-Pe)
             endif
          End do ! Do in elements iel
          donornuclei=max(donornuclei,1e-20*totalnuclei)
          Pg4(loop)=(totalnuclei/donornuclei)*Pe4(loop)
          Pg4(loop)=Pg4(loop)+Pe4(loop) ! Add electron contribution to gas pressure
       End do ! Do in depth points loop
       Call Time_routine('compute_pg',.False.)
       Return
    End if ! End use ANN

    If (eqstate_switch .eq. 1) then ! Use ANNs only
       metalicity=At_abund(26)-7.5
       T4=temper_in
       P4=Pe_in
       Do loop = 1, n_grid
          Call ann_pgfrompe(T4(loop), P4(loop), metalicity, Pg4(loop))
       End do
       Call Time_routine('compute_pg',.False.)
       Return
    End if

    If (eqstate_switch .eq. 2) then ! Use Wittmann's
       Call wittmann_compute_pg(n_grid, temp4, Pe4, Pg4)
       Call Time_routine('compute_pg',.False.)
       Return
    End if

    print *,'Unknown value for Eq state in compute_pe, eq_state.f90'
    stop
    
  End Subroutine Compute_Pg


End Module Eq_state
