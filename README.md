# Systolic-Matrix-Multiplier
Built off the 8x8 matrix multiplier made in EEC 180 (check the EEC 180 repo for lab 6).

Yeah after looking at the matrix multiplier made in EEC 180, probably only gonna use the MACs. We made it do the actual matrix multiplication in the testbench by instantiating a bunch of multiply accumulate units. How in the world did this thing work.

# Results

## Matrix Multiplication
![Matrix mult](Images/Matrix%20mult.png)

## Systolic Matrix Multiplication-behavioral
![Systolic mult](Images/Systolic%20mult.png)

As we can see, the normal matrix multiplication for an 8x8 matrix takes well over 5,000,000ns, whereas the systolic version takes just over 200ns. The systolic matrix multiplication is around ~x25,000 faster than the normal matrix multiplier. This is due to the inherent nature of systolic matrix multiplication. Normal matrix multiplication is done in a "nested loops" way, with lots of memory accesses and waiting for things to finish. This is incredibly slow, and is reflected in the overall computation time (5,000,000ns is 0.005s). Systolic multiplication uses a grid of processing elements that pass the resultant data along to the next processing element, bypassing the need for memory accesses and thus drastically improving calculation time.

# Layout

I am still working on improving the layout. Right now there are two versions of the design-a structural version and a behaioral version. The structural version uses multiply accumulate modules inspired by [this](https://ieeexplore.ieee.org/document/10435014) paper. It uses a radix-2 kogge stone adder and a wallace tree multiplier implementing Booth's alogrithm defined strucutrally in each multiply accumulate module. The idea of this structural design was to optimize for power efficiency while retaining high throughput via wide parallelism. In the second version of the design, the multply accumulate modules are designed behaviorally, leaving it up to the synthesizer to infer what design should be used. As a result this behavioral design is much more area efficient as opposed to the structural design. Both of the designs shown below are full RTL-to-GDSII flows done exclusively in OpenLane2. My future work includes using Synopsys ICC2 to layout my synthesized design from Design Compiler, as well as making hardened macros for each processing element and multiply accumulate module to create a fully custom layout.

# Gate level Layout (Design Compiler)
![layout](Images/systolic%20matrix%20multiplier.png)

# Structural Layout
![layout](Images/systolic_efficient.png)

# Behavioral Layout
![layout](Images/Layout.png)

## Placement Density

![placement density](Images/Placement%20density.png)

## Power Density

Yeah idk why the power density is not working. Uploaded the VCD file successfully and it's still not giving me anything. I'll troubleshoot later:tm:.

![power density](Images/Power%20density.png)

## Routing Congestion

![routing congestion](Images/Routing%20congestion.png)

## Estimated Routing Congestion (RUDY)

![RUDY](Images/Estimated%20congestion.png)

## IR Drop

IR drop has not been populated with data, and idk how to fix it. I'll fix it later:tm:.

![IR Drop](Images/IR%20Drop.png)
