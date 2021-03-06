#' Time-varying TAD boundary analysis
#'
#' @import dplyr
#' @import magrittr
#' @import PRIMME
#' @importFrom HiCcompare sparse2full
#' @param cont_mats List of contact matrices in either sparse 3 column,
#' n x n or n x (n+3) form where the first three columns are coordinates in
#' BED format. See "Input_Data" vignette for more information. 
#' If an n x n matrix is used, the column names must correspond to the start
#' point of the corresponding bin. Required.
#' @param resolution Resolution of the data. Used to assign TAD boundaries
#' to genomic regions. If not provided, resolution will be estimated from
#' column names of the first matrix. Default is "auto".
#' @param z_thresh Threshold for boundary score. Higher values result in a
#' more stringent detection of differential TADs. Default is 3.
#' @param window_size Size of sliding window for TAD detection, measured in bins.
#' Results should be consistent. Default is 15.
#' @param gap_thresh Required \% of non-zero entries before a region will
#' be considered non-informative and excluded. Default is .2
#' @param groupings Variable for defining groups of replicates at a given
#' time point. Each group will be combined using consensus boundary scores.
#' It should be a vector of equal length to cont_mats where each entry is a
#' label corresponding to the group membership of the corresponding
#' matrix. Default is NULL, implying one matrix per time point.
#' @return A list containing consensus TAD boundaries and overall scores
#'  \itemize{
#'  \item TAD_Bounds - Data frame containing all regions with a TAD boundary
#'  at one or more time point. Coordinate corresponds to genomic region, sample
#'  columns correspond to individual boundary scores for each sample,
#'  Consensus_Score is the consensus boundary score across all samples.
#'  Category is the differential boundary type.
#'  \item All_Bounds - Data frame containing consensus scores for all regions
#'  \item Count_Plot - Plot containing the prevelance of each boundary type
#' }
#' @export
#' @details Given a list of sparse 3 column, n x n, or n x (n+3) contact
#' matrices representing different time points, TimeCompare identifies all
#' TAD boundaries. Each TAD boundary is classified  into six categories 
#' (Common, Dynamic,  Early/Late Appearing and Early/Late Disappearing),
#' based on how it changes over time.
#' @examples
#' # Read in data
#' data("time_mats")
#' # Find time varying TAD boundaries
#' diff_list <- TimeCompare(time_mats, resolution = 50000)


TimeCompare = function(cont_mats,
                       resolution,
                      z_thresh = 2,
                      window_size = 15,
                      gap_thresh = .2,
                      groupings = NULL) {

  #Get dimensions of first contact matrix
  row_test = dim(cont_mats[[1]])[1]
  col_test = dim(cont_mats[[1]])[2]

  if (row_test == col_test) {
    if (all(is.finite(cont_mats[[1]])) == FALSE) {
      stop("Contact matrix 1 contains non-numeric entries")
    }

  }

  if (col_test == 3) {


    #Convert sparse matrix to n x n matrix

    message("Converting to n x n matrix")

    cont_mats = lapply(cont_mats, HiCcompare::sparse2full)

    if (all(is.finite(cont_mats[[1]])) == FALSE) {
      stop("Contact matrix 1 contains non-numeric entries")
    }

    if (resolution == "auto") {
      message("Estimating resolution")
      resolution = as.numeric(names(table(as.numeric(colnames(cont_mats[[1]]))-
                                            lag(
                                              as.numeric(
                                                colnames(
                                                  cont_mats[[1]])))))[1])
    }

  } else if (col_test-row_test == 3) {

    message("Converting to n x n matrix")

    cont_mats = lapply(cont_mats, function(x) {
      #Find the start coordinates based on the second column of the bed file
      #portion of matrix

      start_coords = x[,2]

      #Calculate resolution based on given bin size in bed file

      resolution = as.numeric(x[1,3])-as.numeric(x[1,2])

      #Remove bed file portion

      x = as.matrix(x[,-c(seq_len(3))])

      if (all(is.finite(x)) == FALSE) {
        stop("Contact matrix contains non-numeric entries")
      }


      #Make column names correspond to bin start

      colnames(x) = start_coords
      return(x)
    })

  } else if (col_test!=3 & (row_test != col_test) & (col_test-row_test != 3)) {

    #Throw error if matrix does not correspond to known matrix type

    stop("Contact matrix must be sparse or n x n or n x (n+3)!")

  } else if ( (resolution == "auto") & (col_test-row_test == 0) ) {

    message("Estimating resolution")

    #Estimating resolution based on most common distance between loci

    resolution = as.numeric(names(table(as.numeric(colnames(cont_mats[[1]]))-
                                          lag(
                                            as.numeric(
                                              colnames(
                                                cont_mats[[1]])))))[1])
  }

  #Calculate boundary scores
  bound_scores = lapply(seq_len(length(cont_mats)), function(x) {

    dist_sub = .single_dist(cont_mats[[x]], resolution, window_size = window_size)
    dist_sub = data.frame(Sample = paste("Sample", x), dist_sub[,c(2,3)])
    dist_sub
  })


  #Reduce matrices to only include shared regions
  coord_sum = lapply(bound_scores, function(x) x[,2])
  shared_cols = Reduce(intersect, coord_sum)
  bound_scores = lapply(bound_scores, function(x) x %>%
                          filter(as.numeric(Coordinate) %in% as.numeric(shared_cols)))

  #Bind boundary scores
  score_frame = bind_rows(bound_scores)

  #Set column names for base sample
  colnames(score_frame)[1] = "Sample"
  base_sample = score_frame %>% filter(Sample == "Sample 1")

  #Check if user specified groups
  if (!is.null(groupings)) {
    #Map groupings to samples
    Group_Frame = data.frame(Groups = groupings,
                             Sample = unique(score_frame$Sample))

    #Join to replace sample with group
    score_frame = left_join(score_frame, Group_Frame) %>%
      dplyr::select(Sample = Groups, Coordinate, Boundary)

    score_frame = score_frame %>% group_by(Sample, Coordinate) %>%
      mutate(Boundary = median(Boundary)) %>% distinct()
  }

  #Get differences and convert to boundary scores

  score_frame = score_frame %>% group_by(Sample)  %>%
    mutate(Diff_Score = (base_sample$Boundary-Boundary)) %>%
    ungroup() %>% mutate(Diff_Score = (Diff_Score-
                           mean(Diff_Score, na.rm = TRUE))/
                           sd(Diff_Score, na.rm =TRUE)) %>% ungroup() %>%
                           mutate(
                           TAD_Score = (Boundary-mean(Boundary, na.rm = TRUE))/
                           sd(Boundary, na.rm = TRUE)
                           )

  #Determine if boundaries are differential or non-differential
  score_frame = score_frame %>%
    mutate(Differential = ifelse(abs(Diff_Score)>z_thresh,
                                       "Differential", "Non-Differential"),
                                       Differential = ifelse(is.na(Diff_Score),
                                                            "Non-Differential",
                                                             Differential))

  #Getting a frame summarizing boundaries

  TAD_Frame = score_frame %>% dplyr::select(Sample, Coordinate, TAD_Score) %>%
    arrange(as.numeric(gsub("Sample", "", Sample))) %>%
    mutate(Sample = factor(Sample, levels = unique(Sample)))


  #Spread into wide format
  TAD_Frame = tidyr::spread(as.data.frame(TAD_Frame),
                            key = Sample,
                            value = TAD_Score)

  #Get median of boundary scores for each row

  TAD_Frame = TAD_Frame %>%
    mutate(Consensus_Score =
    apply(TAD_Frame %>% dplyr::select(-Coordinate) %>% as.matrix(.)
          ,1, median))

  #Subset differential frame to only include differential points

  Differential_Points = score_frame %>% filter(Differential == "Differential")

  #Pulling out consensus for classification

  TAD_Iden = TAD_Frame[,c(-1, -ncol(TAD_Frame))]>3

  #Classify time trends
  All_Non_TADs = apply(TAD_Iden, 1, function(x) all(x == FALSE))

  #Split into 4 groups for summarization
  Num_Points = seq_len(ncol(TAD_Iden))

  four_groups = split(Num_Points, ggplot2::cut_number(Num_Points,4))

  #Get summary for each group and put back together

  Full_Sum = do.call(cbind.data.frame,
          lapply(four_groups, function(x) (rowSums(as.matrix(TAD_Iden[,x]))/
    ncol(as.matrix(TAD_Iden[,x])))>=.5))

  #Define Highly Common TADs
  Common_TADs = (Full_Sum[,1] == Full_Sum[,2]) &
     (Full_Sum[,1] == Full_Sum[,ncol(Full_Sum)])

  Common_TADs = ifelse(Common_TADs, "Highly Common TAD", NA)

  #Define Early Appearing TADs
  Early_Appearing = (Full_Sum[,1] != Full_Sum[,2]) &
    (Full_Sum[,1] ==FALSE) &
    (Full_Sum[,2] == Full_Sum[,ncol(Full_Sum)])

  Early_Appearing = ifelse(Early_Appearing, "Early Appearing TAD", NA)

  #Late Appearing TADs
  Late_Appearing = (Full_Sum[,1] == Full_Sum[,2]) &
    (Full_Sum[,1] ==FALSE) &
    (Full_Sum[,1] != Full_Sum[,ncol(Full_Sum)])

  Late_Appearing = ifelse(Late_Appearing, "Late Appearing TAD", NA)

  #Early disappearing TADs
  Early_Disappearing = (Full_Sum[,1] != Full_Sum[,2]) &
    (Full_Sum[,1] == TRUE) &
    (Full_Sum[,2] == Full_Sum[,ncol(Full_Sum)])

  Early_Disappearing = ifelse(Early_Disappearing, "Early Disappearing TAD", NA)

  #Late disapearing TADs
  Late_Disappearing = (Full_Sum[,1] == Full_Sum[,2]) &
    (Full_Sum[,1] == TRUE) &
    (Full_Sum[,1] != Full_Sum[,ncol(Full_Sum)])

  Late_Disappearing = ifelse(Late_Disappearing, "Late Disappearing TAD", NA)

  #Dynamic TAD
  Dynamic = (Full_Sum[,1] != Full_Sum[,2]) &
    (Full_Sum[,1] == Full_Sum[,ncol(Full_Sum)])

  Dynamic = ifelse(Dynamic, "Dynamic TAD", NA)

  TAD_Cat = dplyr::coalesce(as.character(Common_TADs),
                     as.character(Early_Appearing),
                     as.character(Late_Appearing),
                     as.character(Early_Disappearing),
                     as.character(Late_Disappearing),
                     as.character(Dynamic))

  TAD_Frame = TAD_Frame %>% dplyr::mutate(Category = TAD_Cat)

  TAD_Frame_Sub = TAD_Frame %>%
    dplyr::filter_at(dplyr::vars(`Sample 1`:Consensus_Score),
                     dplyr::any_vars(.>3))

  TAD_Sum = TAD_Frame_Sub %>% group_by(Category) %>% summarise(Count = n())

  Count_Plot = ggplot(TAD_Sum,
                      aes(x = 1,
                          y = Count, fill = Category)) +
    geom_bar(stat="identity") + theme_bw(base_size = 24) +
    theme(axis.title.x = element_blank(), panel.grid = element_blank(),
          axis.text.x = element_blank(), axis.ticks.x = element_blank()) +
    labs(y = "Number of Boundaries")

  return(list(TAD_Bounds = TAD_Frame_Sub,
              All_Bounds = TAD_Frame,
              Count_Plot = Count_Plot))
}

.single_dist = function(cont_mat1,
                        resolution,
                        window_size = 15,
                        gap_thresh = .2) {

  #Remove full gaps from matrices

  non_gaps = which(colSums(cont_mat1) !=0)

  cont_mat_filt = cont_mat1[non_gaps,non_gaps]

  #Setting window size parameters
  max_end = window_size

  start = 1
  end = max_end

  end_loop = 0

  if ( (end+window_size)>nrow(cont_mat_filt)) {
    end = nrow(cont_mat_filt)
  }

  point_dists1 = rbind()

  while (end_loop == 0) {

    #Get windowed portion of matrix
    sub_filt1 = cont_mat_filt[seq(start,end,1), seq(start,end,1)]

    #Identify columns with more than the gap threshold of zeros
    Per_Zero1 = (colSums(sub_filt1 !=0)/nrow(sub_filt1))<gap_thresh

    #Remove rows and dcolumns with zeros above gap threshold
    sub_filt1 = sub_filt1[!Per_Zero1, !Per_Zero1]

    #Test if matrix is too small to analyze
    if ((length(sub_filt1) == 0) | (length(sub_filt1) == 1)) {
      if (end == nrow(cont_mat1)) {
        end_loop = 1
      }

      #Move window to next point
      start = end
      end = end+max_end

      #Check if window is overlapping end of matrix and shorten if so
      if ( (end + max_end) >nrow(cont_mat_filt)) {
        end = nrow(cont_mat_filt)
      }

      #Check if matrix starts at end of matrix and kill loop
      if (start == end | start>nrow(cont_mat_filt)) {
        end_loop = 1
      }
      next
    }

    #Creating the normalized laplacian

    #Calculate row sums (degrees)
    dr1 = rowSums(abs(sub_filt1))

    #Perturbation factor for stability
    Dinvsqrt1 = diag((1/sqrt(dr1+2e-16)))

    #Form degree matrix
    P_Part1 = crossprod(as.matrix(sub_filt1), Dinvsqrt1)
    sub_mat1 = crossprod(Dinvsqrt1, P_Part1)

    #sub_mat = crossprod(diag(dr^-(1/2)), as.matrix(sub_filt))

    #Set column names to match original matrix
    colnames(sub_mat1) = colnames(sub_filt1)

    #Get first two eigenvectors

    Eigen1 = eigs_sym(sub_mat1, NEig = 2)

    #Pull out eigenvalues and eigenvectors
    eig_vals1 = Eigen1$values
    eig_vecs1 = Eigen1$vectors

    #Get order of eigenvalues from largest to smallest

    large_small1 = order(-eig_vals1)

    eig_vals1 = eig_vals1[large_small1]
    eig_vecs1 = eig_vecs1[,large_small1]

    #Normalize the eigenvectors

    norm_ones = sqrt(dim(sub_mat1)[2])

    for (i in seq_len(dim(eig_vecs1)[2])) {
      eig_vecs1[,i] = (eig_vecs1[,i]/sqrt(sum(eig_vecs1[,i]^2)))  * norm_ones
      if (eig_vecs1[1,i] !=0) {
        eig_vecs1[,i] = -1*eig_vecs1[,i] * sign(eig_vecs1[1,i])
      }
    }

    #Get rows and columns of contact matrix

    n = dim(eig_vecs1)[1]
    k = dim(eig_vecs1)[2]

    #Project eigenvectors onto a unit circle

    vm1 = matrix(kronecker(rep(1,k),
                           as.matrix(sqrt(rowSums(eig_vecs1^2)))),n,k)
    eig_vecs1 = eig_vecs1/vm1

    #Get distance between points on circle

    point_dist1 = sqrt(
        rowSums( (eig_vecs1-rbind(NA,eig_vecs1[-nrow(eig_vecs1),]))^2)
                      )

    #Match column names (Coordinates) with eigenvector distances
    point_dist1 = cbind( match(colnames(sub_mat1),colnames(cont_mat1)),
                         as.numeric(colnames(sub_mat1)), point_dist1)

    #Combine current distances with old distances
    point_dists1 = rbind(point_dists1, point_dist1[-1,])

    #Check if window is at the end of matrix and kill loop
    if (end == nrow(cont_mat1)) {
      end_loop = 1
    }

    #Reset window
    start = end
    end = end+max_end

    #Check if window is near end of matrix and expand to end if true
    if ( (end + max_end) >nrow(cont_mat_filt)) {
      end = nrow(cont_mat_filt)
    }

    #Check if start of window overlaps end of matrix and kill if true
    if (start == end | start>nrow(cont_mat_filt)) {
      end_loop = 1
    }
  }

  #Convert to data frame
  point_dists1 = as.data.frame(point_dists1)
  colnames(point_dists1) = c("Index", "Coordinate","Boundary")
  return(point_dists1 = point_dists1)
}


