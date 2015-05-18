## Developer Cloud Sandbox interferogram processing with StaMPS


StaMPS (Stanford Method for Persistent Scatterers) is a software package that implements an InSAR persistent scatterer (PS) method developed to work even in terrains devoid of man-made structures and/or undergoing non-steady deformation. StaMPS/MTI (Multi-Temporal InSAR) is an extended version of StaMPS that also includes a small baseline method and a combined multi-temporal InSAR method. The original development of StaMPS was undertaken at Stanford University, but subsequent development of StaMPS and StaMPS/MTI has taken place at the University of Iceland and Delft University of Technology.

## Quick link
 
* [Getting Started](#getting-started)
* [Installation](#installation)
* [Submitting the workflow](#submit)
* [Community and Documentation](#community)
* [Authors](#authors)
* [Questions, bugs, and suggestions](#questions)
* [License](#license)

### <a name="getting-started"></a>Getting Started 

To run this application you will need a Developer Cloud Sandbox, that can be either requested from:
* ESA [Geohazards Exploitation Platform](https://geohazards-tep.eo.esa.int) for GEP early adopters;
* ESA [Research & Service Support Portal](http://eogrid.esrin.esa.int/cloudtoolbox/) for ESA G-POD related projects and ESA registered user accounts
* From [Terradue's Portal](http://www.terradue.com/partners), provided user registration approval. 

A Developer Cloud Sandbox provides Earth Sciences data access services, and helper tools for a user to implement, test and validate a scalable data processing application. It offers a dedicated virtual machine and a Cloud Computing environment.
The virtual machine runs in two different lifecycle modes: Sandbox mode and Cluster mode. 
Used in Sandbox mode (single virtual machine), it supports cluster simulation and user assistance functions in building the distributed application.
Used in Cluster mode (a set of master and slave nodes), it supports the deployment and execution of the application with the power of distributed computing for data processing over large datasets (leveraging the Hadoop Streaming MapReduce technology). 
### <a name="installation"></a>Installation

#### Pre-requisites

Downgrade *geos* to version 3.3.2:

```bash
sudo yum -y downgrade geos-3.3.2
```

##### Using the releases

Log on the developer cloud sandbox. Download the rpm package from https://github.com/Terradue/dcs-stamps-ps/releases.
Install the dowanloaded package by running these commands in a shell:

```bash
sudo yum -y install dcs-stamps-ps-<version>.x86_64.rpm
```

#### Using the development version

Log on the developer sandbox and run these commands in a shell:

```bash
sudo yum -y install adore-t2 python-lxml sar-helpers StaMPS-t2-mcr matlab717
git clone git@github.com:Terradue/dcs-stamps-ps.git
cd dcs-stamps-ps
mvn install
```

### <a name="submit"></a>Submitting the workflow

Run this command in a shell:

```bash
ciop-run
```
Or invoke the Web Processing Service via the Sandbox dashboard or the [Geohazards Thematic Exploitation platform](https://geohazards-tep.eo.esa.int) providing a master, a stack of slave product URLs and orbit file specification (for Envisat DOR or ODR, ERS ODR):

### <a name="community"></a>Community and Documentation

To learn more and find information go to 

* [Developer Cloud Sandbox](http://docs.terradue.com/developer) service 
* [StaMPS](http://homepages.see.leeds.ac.uk/~earahoo/stamps/StaMPS_Manual_v3.1.pdf)
* [ESA Geohazards Exploitation Platform](https://geohazards-tep.eo.esa.int)

### <a name="authors"></a>Authors (alphabetically)

* Brito Fabrice
* D'Andria Fabio
* Vollrath Andreas

### <a name="questions"></a>Questions, bugs, and suggestions

Please file any bugs or questions as [issues](https://github.com/geohazards-tep/dcs-doris-ifg/issues/new) or send in a pull request.

### <a name="license"></a>License

Copyright 2015 Terradue Srl

Licensed under the Apache License, Version 2.0: http://www.apache.org/licenses/LICENSE-2.0
