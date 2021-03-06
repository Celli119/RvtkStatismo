% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/vtkTriangulate.r
\name{vtkTriangulate}
\alias{vtkTriangulate}
\title{create Isosurface from image}
\usage{
vtkTriangulate(file, value = 1, IJK2RAS = diag(c(-1, -1, 1, 1)),
  dicom = FALSE)
}
\arguments{
\item{file}{3D-image file mha/nii.gz - depending of your system's VTK version}

\item{value}{isovalue}

\item{IJK2RAS}{4x4 IJK2RAS transform}

\item{dicom}{logical: if TRUE, \code{file} points to a directory containing a set of DICOM files belonging to a single series. See notes.}
}
\value{
returns a triangular mesh of class mesh3d
}
\description{
create Isosurface from image
}
\note{
the dicom functionality only works for unencapsulated raw dicom files. In case of errors, deencapsulate your files first. This can be done, for example, with the command line tool \code{gdcmconv}.
}

