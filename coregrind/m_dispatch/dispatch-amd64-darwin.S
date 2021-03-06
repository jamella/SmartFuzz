
/*--------------------------------------------------------------------*/
/*--- The core dispatch loop, for jumping to a code address.       ---*/
/*---                                      dispatch-amd64-darwin.S ---*/
/*--------------------------------------------------------------------*/

/*
  This file is part of Valgrind, a dynamic binary instrumentation
  framework.

  Copyright (C) 2000-2007 Julian Seward 
     jseward@acm.org

  This program is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 2 of the
  License, or (at your option) any later version.

  This program is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
  02111-1307, USA.

  The GNU General Public License is contained in the file COPYING.
*/

#include "pub_core_basics_asm.h"
#include "pub_core_dispatch_asm.h"
#include "pub_core_transtab_asm.h"
#include "libvex_guest_offsets.h"	/* for OFFSET_amd64_RIP */


/*------------------------------------------------------------*/
/*---                                                      ---*/
/*--- The dispatch loop.  VG_(run_innerloop) is used to    ---*/
/*--- run all translations except no-redir ones.           ---*/
/*---                                                      ---*/
/*------------------------------------------------------------*/

/*----------------------------------------------------*/
/*--- Preamble (set everything up)                 ---*/
/*----------------------------------------------------*/

/* signature:
UWord VG_(run_innerloop) ( void* guest_state, UWord do_profiling );
*/

.text
.globl VG_(run_innerloop)
VG_(run_innerloop):
	/* %rdi holds guest_state */
	/* %rsi holds do_profiling */
	
	/* ----- entry point to VG_(run_innerloop) ----- */
	pushq	%rbx
	pushq	%rcx
	pushq	%rdx
	pushq	%rsi
	pushq	%rbp
	pushq	%r8
	pushq	%r9
	pushq	%r10
	pushq	%r11
	pushq	%r12
	pushq	%r13
	pushq	%r14
	pushq	%r15
	pushq	%rdi  /* guest_state */

	movq	VG_(dispatch_ctr)@GOTPCREL(%rip), %r15
	movl	(%r15), %r15d
	pushq	%r15

	/* 8(%rsp) holds cached copy of guest_state ptr */
	/* 0(%rsp) holds cached copy of VG_(dispatch_ctr) */

	/* Set up the guest state pointer */
	movq	%rdi, %rbp
	
	/* fetch %RIP into %rax */
	movq	OFFSET_amd64_RIP(%rbp), %rax

	/* set host FPU control word to the default mode expected 
           by VEX-generated code.  See comments in libvex.h for
           more info. */
	finit
	pushq	$0x027F
	fldcw	(%rsp)
	addq	$8, %rsp
	
	/* set host SSE control word to the default mode expected 
	   by VEX-generated code. */
	pushq	$0x1F80
	ldmxcsr	(%rsp)
	addq	$8, %rsp

	/* set dir flag to known value */
	cld

	/* fall into main loop  (the right one) */
	cmpq	$0, %rsi
	je	VG_(run_innerloop__dispatch_unprofiled)
	jmp	VG_(run_innerloop__dispatch_profiled)
	/*NOTREACHED*/	

/*----------------------------------------------------*/
/*--- NO-PROFILING (standard) dispatcher           ---*/
/*----------------------------------------------------*/

.align	4
.globl	VG_(run_innerloop__dispatch_unprofiled)
VG_(run_innerloop__dispatch_unprofiled):
	/* AT ENTRY: %rax is next guest addr, %rbp is possibly
           modified guest state ptr */

	/* Has the guest state pointer been messed with?  If yes, exit. */
	cmpq	8(%rsp), %rbp
	movq	VG_(tt_fast)@GOTPCREL(%rip), %rcx
	jnz	gsp_changed

	/* save the jump address in the guest state */
	movq	%rax, OFFSET_amd64_RIP(%rbp)

	/* Are we out of timeslice?  If yes, defer to scheduler. */
	subl	$1, 0(%rsp)
	jz	counter_is_zero

	/* try a fast lookup in the translation cache */
	movq	%rax, %rbx
	andq	$VG_TT_FAST_MASK, %rbx	/* entry# */
	shlq	$4, %rbx		/* entry# * sizeof(FastCacheEntry) */
	movq	0(%rcx,%rbx,1), %r10	/* .guest */
	movq	8(%rcx,%rbx,1), %r11	/* .host */
	cmpq	%rax, %r10
	jnz	fast_lookup_failed

        /* Found a match.  Jump to .host. */
	jmp 	*%r11
	ud2	/* persuade insn decoders not to speculate past here */
	/* generated code should run, then jump back to
	   VG_(run_innerloop__dispatch_unprofiled). */
	/*NOTREACHED*/

/*----------------------------------------------------*/
/*--- PROFILING dispatcher (can be much slower)    ---*/
/*----------------------------------------------------*/

.align	4
.globl	VG_(run_innerloop__dispatch_profiled)
VG_(run_innerloop__dispatch_profiled):
	/* AT ENTRY: %rax is next guest addr, %rbp is possibly
           modified guest state ptr */

	/* Has the guest state pointer been messed with?  If yes, exit. */
	cmpq	8(%rsp), %rbp
	movq	VG_(tt_fast)@GOTPCREL(%rip), %rcx
	jnz	gsp_changed

	/* save the jump address in the guest state */
	movq	%rax, OFFSET_amd64_RIP(%rbp)

	/* Are we out of timeslice?  If yes, defer to scheduler. */
	subl	$1, 0(%rsp)
	jz	counter_is_zero

	/* try a fast lookup in the translation cache */
	movq	%rax, %rbx
	andq	$VG_TT_FAST_MASK, %rbx	/* entry# */
	shlq	$4, %rbx		/* entry# * sizeof(FastCacheEntry) */
	movq	0(%rcx,%rbx,1), %r10	/* .guest */
	movq	8(%rcx,%rbx,1), %r11	/* .host */
	cmpq	%rax, %r10
	jnz	fast_lookup_failed

	/* increment bb profile counter */
	movq	VG_(tt_fastN)@GOTPCREL(%rip), %rdx
	shrq	$1, %rbx		/* entry# * sizeof(UInt*) */
	movq	(%rdx,%rbx,1), %rdx
	addl	$1, (%rdx)

        /* Found a match.  Jump to .host. */
	jmp 	*%r11
	ud2	/* persuade insn decoders not to speculate past here */
	/* generated code should run, then jump back to
	   VG_(run_innerloop__dispatch_profiled). */
	/*NOTREACHED*/

/*----------------------------------------------------*/
/*--- exit points                                  ---*/
/*----------------------------------------------------*/

gsp_changed:
	/* Someone messed with the gsp.  Have to
           defer to scheduler to resolve this.  dispatch ctr
	   is not yet decremented, so no need to increment. */
	/* %RIP is NOT up to date here.  First, need to write
	   %rax back to %RIP, but without trashing %rbp since
	   that holds the value we want to return to the scheduler.
	   Hence use %r15 transiently for the guest state pointer. */
	movq	8(%rsp), %r15
	movq	%rax, OFFSET_amd64_RIP(%r15)
	movq	%rbp, %rax
	jmp	run_innerloop_exit
	/*NOTREACHED*/

counter_is_zero:
	/* %RIP is up to date here */
	/* back out decrement of the dispatch counter */
	addl	$1, 0(%rsp)
	movq	$VG_TRC_INNER_COUNTERZERO, %rax
	jmp	run_innerloop_exit

fast_lookup_failed:
	/* %RIP is up to date here */
	/* back out decrement of the dispatch counter */
	addl	$1, 0(%rsp)
	movq	$VG_TRC_INNER_FASTMISS, %rax
	jmp	run_innerloop_exit



/* All exits from the dispatcher go through here.  %rax holds
   the return value. 
*/
run_innerloop_exit: 
	/* We're leaving.  Check that nobody messed with
           %mxcsr or %fpucw.  We can't mess with %rax here as it
	   holds the tentative return value, but any other is OK. */
#if !defined(ENABLE_INNER)
        /* This check fails for self-hosting, so skip in that case */
	pushq	$0
	fstcw	(%rsp)
	cmpl	$0x027F, (%rsp)
	popq	%r15 /* get rid of the word without trashing %eflags */
	jnz	invariant_violation
#endif
	pushq	$0
	stmxcsr	(%rsp)
	andl	$0xFFFFFFC0, (%rsp)  /* mask out status flags */
	cmpl	$0x1F80, (%rsp)
	popq	%r15
	jnz	invariant_violation
	/* otherwise we're OK */
	jmp	run_innerloop_exit_REALLY

invariant_violation:
	movq	$VG_TRC_INVARIANT_FAILED, %rax
	jmp	run_innerloop_exit_REALLY

run_innerloop_exit_REALLY:

	/* restore VG_(dispatch_ctr) */	
	popq	%r14
	movq	VG_(dispatch_ctr)@GOTPCREL(%rip), %r15
	movl	%r14d, (%r15)

	popq	%rdi
	popq	%r15
	popq	%r14
	popq	%r13
	popq	%r12
	popq	%r11
	popq	%r10
	popq	%r9
	popq	%r8
	popq	%rbp
	popq	%rsi
	popq	%rdx
	popq	%rcx
	popq	%rbx
	ret	

	
/*------------------------------------------------------------*/
/*---                                                      ---*/
/*--- A special dispatcher, for running no-redir           ---*/
/*--- translations.  Just runs the given translation once. ---*/
/*---                                                      ---*/
/*------------------------------------------------------------*/

/* signature:
void VG_(run_a_noredir_translation) ( UWord* argblock );
*/

/* Run a no-redir translation.  argblock points to 4 UWords, 2 to carry args
   and 2 to carry results:
      0: input:  ptr to translation
      1: input:  ptr to guest state
      2: output: next guest PC
      3: output: guest state pointer afterwards (== thread return code)
*/
.align 4
.globl VG_(run_a_noredir_translation)
VG_(run_a_noredir_translation):
	/* Save callee-saves regs */
	pushq %rbx
	pushq %rbp
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15

	pushq %rdi  /* we will need it after running the translation */
	movq 8(%rdi), %rbp
	jmp *0(%rdi)
	/*NOTREACHED*/
	ud2
	/* If the translation has been correctly constructed, we
	should resume at the the following label. */
.globl VG_(run_a_noredir_translation__return_point)
VG_(run_a_noredir_translation__return_point):
	popq %rdi
	movq %rax, 16(%rdi)
	movq %rbp, 24(%rdi)

	popq  %r15
	popq  %r14
	popq  %r13
	popq  %r12
	popq  %rbp
	popq  %rbx
	ret

/*--------------------------------------------------------------------*/
/*--- end                                                          ---*/
/*--------------------------------------------------------------------*/
