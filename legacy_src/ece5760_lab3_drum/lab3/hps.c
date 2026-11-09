///////////////////////////////////////
/// 640x480 version! 16-bit color
/// This code will segfault the original
/// DE1 computer
/// compile with
/// gcc hps.c -o hps_lab3 -O2 -lm
///
///////////////////////////////////////
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/ipc.h> 
#include <sys/shm.h> 
#include <sys/mman.h>
#include <sys/time.h> 
#include <math.h>
//#include "address_map_arm_brl4.h"

// video display
#define SDRAM_BASE            0xC0000000
#define SDRAM_END             0xC3FFFFFF
#define SDRAM_SPAN			  0x04000000
// characters
#define FPGA_CHAR_BASE        0xC9000000 
#define FPGA_CHAR_END         0xC9001FFF
#define FPGA_CHAR_SPAN        0x00002000
/* Cyclone V FPGA devices */
#define HW_REGS_BASE          0xff200000
//#define HW_REGS_SPAN        0x00200000 
#define HW_REGS_SPAN          0x00005000 

// === the fixed point macros (1.17) ========================================
typedef signed int fix17;
#define int2fix(a) ((fix17)((a) << 17))
#define fix2int(a) ((int)((a) >> 17))

#define float2fix(a) ((fix17)((a) * 131072.0))
#define fix2float(a) ((float)(a) / 131072.0)

//define pio offset
#define PIO0_OFFSET 0x00
#define PIO1_OFFSET 0x10
#define PIO2_OFFSET 0x20
#define PIO3_OFFSET 0x30

// graphics primitives
void VGA_text (int, int, char *);
void VGA_text_clear();
void VGA_box (int, int, int, int, short);
void VGA_rect (int, int, int, int, short);
void VGA_line(int, int, int, int, short) ;
void VGA_Vline(int, int, int, short) ;
void VGA_Hline(int, int, int, short) ;
void VGA_disc (int, int, int, short);
void VGA_circle (int, int, int, int);
// 16-bit primary colors
#define red  (0+(0<<5)+(31<<11))
#define dark_red (0+(0<<5)+(15<<11))
#define green (0+(63<<5)+(0<<11))
#define dark_green (0+(31<<5)+(0<<11))
#define blue (31+(0<<5)+(0<<11))
#define dark_blue (15+(0<<5)+(0<<11))
#define yellow (0+(63<<5)+(31<<11))
#define cyan (31+(63<<5)+(0<<11))
#define magenta (31+(0<<5)+(31<<11))
#define black (0x0000)
#define gray (15+(31<<5)+(51<<11))
#define white (0xffff)
int colors[] = {red, dark_red, green, dark_green, blue, dark_blue, 
		yellow, cyan, magenta, gray, black, white};

// pixel macro
#define VGA_PIXEL(x,y,color) do{\
	int  *pixel_ptr ;\
	pixel_ptr = (int*)((char *)vga_pixel_ptr + (((y)*640+(x))<<1)) ; \
	*(short *)pixel_ptr = (color);\
} while(0)

// the light weight buss base
void *h2p_lw_virtual_base;

// pixel buffer
volatile unsigned int * vga_pixel_ptr = NULL ;
void *vga_pixel_virtual_base;

// character buffer
volatile unsigned int * vga_char_ptr = NULL ;
void *vga_char_virtual_base;

// /dev/mem file id
int fd;

// measure time
struct timeval t1, t2;
double elapsedTime;
	
int main(void)
{   

     // Open /dev/mem
	if( ( fd = open( "/dev/mem", ( O_RDWR | O_SYNC ) ) ) == -1 ) 	{
		printf( "ERROR: could not open \"/dev/mem\"...\n" );
		return( 1 );
	}
    
    // get virtual addr that maps to physical
	h2p_lw_virtual_base = mmap( NULL, HW_REGS_SPAN, ( PROT_READ | PROT_WRITE ), MAP_SHARED, fd, HW_REGS_BASE );	
	if( h2p_lw_virtual_base == MAP_FAILED ) {
		printf( "ERROR: mmap1() failed...\n" );
		close( fd );
		return(1);
	}
    
	signed int * pio0_test; // number of rows
	signed int * pio1_test; // new rho val
	signed int * pio2_test; // new init amplitude
    // update / reset 
    signed int * pio3_test;  // rest



	pio0_test =(signed int *)(h2p_lw_virtual_base+PIO0_OFFSET);
	pio1_test =(signed int *)(h2p_lw_virtual_base+PIO1_OFFSET);
	pio2_test =(signed int *)(h2p_lw_virtual_base+PIO2_OFFSET);
    pio3_test =(signed int *)(h2p_lw_virtual_base+PIO3_OFFSET);

    int updated = 0;
    char str1;
    int str_n;
    float str_r;
    float str_a;

    while(1) {

        updated = 0;
		
		printf("Enter Command ('n' -> number of rows, 'r' -> rho gain, 'a' -> inital amplitude: \n");
		scanf("%c", &str1);
		if (str1 == 'n') {
			printf("Enter new number of rows as an integer: ");
			scanf("%d", &str_n);
            updated = 1;
		} else if (str1 == 'r') {
			printf("Enter value of the exponential for new rho gain: ");
			scanf("%f", &str_r); 
			powf((float)2, str_r);
            updated = 1;
		} else if (str1 == 'a') {
            printf("Enter new initial amplitude: ");
			scanf("%f", &str_a);
            updated = 1;
        }
        if(updated) {
            *pio0_test = str_n;
			*pio1_test = float2fix(str_r);
			*pio2_test = float2fix(str_a);
        }
        *pio3_test = updated;
    }
    return 0;
} // end main




