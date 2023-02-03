using Plots
using LaTeXStrings
using Measures
using ProgressMeter
using UnPack
using Printf

# Called during ODE solve to see solution progress
function outputs(integrator)

    # Unpack integrator
    sol=integrator.sol 
    p=integrator.p[1]
    r=integrator.p[2]
    @unpack Nz,outPeriod,plotPeriod= p

    # Perform plots on output period 
    modt=mod(sol.t[end],outPeriod)
    if modt≈0.0 || modt≈outPeriod


        # Convert solution to dependent variables
        t,Xt,St,Pb,Sb,Lf=unpack_solutionForPlot(sol,p,r)

        # Print titles to REPL every 10 outPeriod
        if mod(sol.t[end],outPeriod*10)≈0.0 || mod(sol.t[end],outPeriod*10)≈outPeriod*10
            printBiofilmTitles(p)
        end

        # Print values to REPL every 1 outPeriod
        printBiofilmValues(t[end],Xt[:,end],St[:,end],Pb,Sb,Lf[end],p)

        # Plot results
        if p.makePlots && (mod(sol.t[end],plotPeriod)≈0.0 || mod(sol.t[end],plotPeriod)≈plotPeriod)
            makePlots(t,Xt,St,Pb,Sb,Lf,p)
        end

    end
end 

# Take in array and compute reasonable ylimits
function pad_ylim(A)
    ymin=minimum(A)
    ymax=maximum(A)
    yavg=0.5*(ymin+ymax)
    deltay = max(0.1*yavg,0.6*(ymax-ymin))
    return [max(0.0,yavg-deltay),yavg+deltay]
end 

# Make plots
function makePlots(t,Xt,St,Pb,Sb,Lf,p)
    @unpack Nx,Ns,Nz,Title,XNames,SNames,Ptot,rho,srcX,optionalPlot,plotSize = p 

    # Adjust names to work with legends
    Nx==1 ? Xs=XNames[1] : Xs=reshape(XNames,1,length(XNames))
    Ns==1 ? Ss=SNames[1] : Ss=reshape(SNames,1,length(SNames))

    # Compute grid
    z=range(0.0,Lf[end],Nz+1)
    zm=0.5*(z[1:Nz]+z[2:Nz+1])
    dz=z[2]-z[1]
    g=biofilmGrid(z,zm,dz)

    # Tank particulate concentration
    p1=plot(t,Xt',label=Xs,ylim=pad_ylim(Xt))
    xaxis!(L"\textrm{Time~[days]}")
    yaxis!(L"\textrm{Tank~Particulate~Conc.~} [g/m^3]")

    # Tank substrate concentration
    p2=plot(t,St',label=Ss,ylim=pad_ylim(St))
    xaxis!(L"\textrm{Time~[days]}")
    yaxis!(L"\textrm{Tank~Substrate~Conc.~} [g/m^3]")

    # Biofilm thickness
    p3=plot(t,Lf'*1e6,label="Thickness",ylim=pad_ylim(Lf*1e6))
    xaxis!(L"\textrm{Time~[days]}")
    yaxis!(L"\textrm{Biofilm~Thickness~} [μm]")

    # Biofilm particulate volume fractioin 
    p4=plot(1e6.*zm,Pb',label=Xs,ylim=pad_ylim(Pb))
    #p4=plot!(zm,sum(Pb,dims=1)',label="Sum")
    xaxis!(L"\textrm{Height~in~Biofilm~} [\mu m]")
    yaxis!(L"\textrm{Biofilm~Particulate~Vol.~Frac.~[-]}")
    
    # Biofilm substrate concentration
    p5=plot(1e6.*zm,Sb',label=Ss,ylim=pad_ylim(Sb))
    xaxis!(L"\textrm{Height~in~Biofilm~} [\mu m]")
    yaxis!(L"\textrm{Biofilm~Substrate~Conc.~} [g/m^3]")

    # Optional 6th plot
    if optionalPlot == "growthrate"
        # Particulate growthrates vs depth
        Xb=similar(Pb)
        for j=1:Nx
            Xb[j,:] = rho[j]*Pb[j,:]  # Compute particulate concentrations
        end
        μb    = computeMu_biofilm(Sb,Xb,Lf[end],t[end],p,g)   # Growthrates in biofilm
        p6=plot(1e6.*zm,μb',label=Xs,ylim=pad_ylim(μb))
        xaxis!(L"\textrm{Height~in~Biofilm~} [\mu m]")
        yaxis!(L"\textrm{Particulate~Growthrates~[-]}")

    elseif optionalPlot == "source"

        # Particulate source term vs depth
        srcs=similar(Pb)
        for i=1:Nz
            for j=1:Nx
                srcs[j,i]=srcX[j](Sb[:,i],Pb[:,i]*rho[j],t,p)[1]
            end
        end
        p6=plot(1e6.*zm,srcs',label=Xs)
        xaxis!(L"\textrm{Height~in~Biofilm~} [\mu m]")
        yaxis!(L"\textrm{Particulate~Source~} [g/m^3\cdot d]")
    else
        p6=[]
    end

    # Put plots together
    myplt=plot(p1,p2,p3,p4,p5,p6,
        layout=(2,3),
        size=plotSize,
        plot_title=@sprintf("%s : t = %.2f",Title,t[end]),
        #plot_titlevspan=0.5,
        left_margin=10mm, 
        bottom_margin=10mm,
        foreground_color_legend = nothing,
        legend = :outertop,
    )
    display(myplt)
    return
end

# Make plots
function makeBiofilmPlots(t,Pb,Sb,Lf,p,plotSize)
    @unpack Nx,Ns,Nz,Title,XNames,SNames,Ptot,mu,rho,optionalPlot = p 

    # Adjust names to work with legends
    Nx==1 ? Xs=XNames[1] : Xs=reshape(XNames,1,length(XNames))
    Ns==1 ? Ss=SNames[1] : Ss=reshape(SNames,1,length(SNames))

    # Package grid
    z=range(0.0,Lf[end],Nz+1)
    zm=0.5*(z[1:Nz]+z[2:Nz+1])
    dz=z[2]-z[1]
    g=biofilmGrid(z,zm,dz)

    # Make plots
    p1=plot(1e6.*zm,Pb',label=Xs,ylim=pad_ylim(Pb))
    xaxis!(L"\textrm{Height~in~Biofilm~} [\mu m]")
    yaxis!(L"\textrm{Biofilm~Particulate~Vol.~Frac.~[-]}")
    
    p2=plot(1e6.*zm,Sb',label=Ss,ylim=pad_ylim(Sb))
    xaxis!(L"\textrm{Height~in~Biofilm~} [\mu m]")
    yaxis!(L"\textrm{Biofilm~Substrate~Conc.~} [g/m^3]")

    # Optional 3th plot
    if optionalPlot == "growthrate"
        # Particulate growthrates vs depth
        Xb=similar(Pb)
        for j=1:Nx
            Xb[j,:] = rho[j]*Pb[j,:]  # Compute particulate concentrations
        end
        μb    = computeMu_biofilm(Sb,Xb,Lf[end],t[end],p,g)   # Growthrates in biofilm
        p3=plot(1e6.*zm,μb',label=Xs,ylim=pad_ylim(μb))
        xaxis!(L"\textrm{Height~in~Biofilm~} [\mu m]")
        yaxis!(L"\textrm{Particulate~Growthrates~[-]}")

    elseif optionalPlot == "source"

        # Particulate source term vs depth
        srcs=similar(Pb)
        for i=1:Nz
            for j=1:Nx
                srcs[j,i]=srcX[j](Sb[:,i],Pb[:,i]*rho[j],t,p)[1]
            end
        end
        p3=plot(1e6.*zm,srcs',label=Xs)
        xaxis!(L"\textrm{Height~in~Biofilm~} [\mu m]")
        yaxis!(L"\textrm{Particulate~Source~} [g/m^3\cdot d]")
    else
        p3=[]
    end

    # Put plots together
    myplt=plot(p1,p2,p3,
        layout=(1,3),
        size=plotSize,
        plot_title=@sprintf("%s : t = %.2f",Title,t[end]),
        #plot_titlevspan=0.5,
        left_margin=10mm, 
        bottom_margin=10mm,
        foreground_color_legend = nothing,
        legend = :outertop,
    )
    display(myplt)
    return
end