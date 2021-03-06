#' Visualization of differential TAD boundaries
#'
#' @import dplyr
#' @import RColorBrewer
#' @import ggplot2
#' @importFrom cowplot plot_grid
#' @importFrom ggpubr get_legend
#' @importFrom reshape2 melt
#' @param tad_diff Raw object output by TADCompare. Required.
#' @param cont_mat1 contact matrix in either sparse 3 column,
#' n x n or n x (n+3) form where the first three columns are coordinates in
#' BED format. See "Input_Data" vignette for more information. 
#' If an x n matrix is used, the column names must correspond to
#' the start point of the corresponding bin. Should correspond
#' to the first contact matrix input into TADCompare. Required.
#' @param cont_mat2 contact matrix in either sparse 3 column,
#' n x n or n x (n+3) form where the first three columns are coordinates in
#' BED format. If an x n matrix is used, the column names must correspond to
#' the start point of the corresponding bin. Should correspond
#' to the second contact matrix input into TADCompare. Required.
#' @param resolution Resolution of the data. Required.
#' @param start_coord The start coordinate defining a region to plot. Required.
#' @param end_coord The end coordinate defining a region to plot. Required.
#' @param pre_tad A list of pre-defined TADs for drawing. Must contain two
#' entries with the first corresponding to TADs detected in matrix 1 
#' and the second to those detected in matrix 2. Each entry must contain a BED-like
#' data frame or GenomicRanges object with columns "chr", "start", and "end", 
#' corresponding to coordinates of TADs. Must correspond to TADCompare results
#' obtained for the same pre-defined TADs. Optional
#' @param show_types If FALSE only the labels "Differential" and 
#' "Non-Differential" will be used. More in-depth differential boundary types
#' will be excluded. Default is TRUE.
#' @param point_size Parameter used to adjust the size of boundary points on 
#' heatmap plot. Default is 3.
#' @param max_height Maximum height in bins that should be displayed on the
#' heatmap plot. Default is 25.
#' @param rel_heights Proportion of the size of the heatmap and score panels.
#' Should be a vector containing the relative size of each panel with the 
#' heatmap panel coming first and the score panel second. Default is c(2, 1).
#' @param palette Parameter used to adjust color palette. For list of palettes
#' see https://rdrr.io/cran/RColorBrewer/man/ColorBrewer.html. Alternatively,
#' users can define a vector of color names or hex codes.  Default is 'RdYlBu'
#' @return A ggplot plot containing a visualization of the upper diagonal both 
#' contact matrices with types of non-/differential boundaries labeled.
#' The first matrix is shown on top and the second on the bottom. If pre_tad
#' is provided, then the outline of the pre-defined TADs are shown. Individual
#' TAD score and differential TAD scores are shown below the contact matrix
#' plots.
#' @export
#' @details Given a TADCompare object and two corresponding contact matrices,
#' Diff_Plot provides visualization of user-specified regions of the genome
#' with accompanying differential annotations, TAD scores and differential
#' TAD scores
#' @examples
#' # Read in data
#' data("rao_chr22_prim")
#' data("rao_chr22_rep")
#' # Find differential TAD boundaries
#' tad_diff <- TADCompare(rao_chr22_prim, rao_chr22_rep, resolution = 50000)
#' # Create plot
#' DiffPlot(tad_diff,rao_chr22_prim, rao_chr22_rep, resolution = 50000, 
#' start_coord = 22050000, end_coord = 24150000)

DiffPlot = function(tad_diff,
                     cont_mat1, 
                     cont_mat2, 
                     resolution, 
                     start_coord, 
                     end_coord,
                     pre_tad=NULL,
                     show_types = TRUE,
                     point_size=3,
                     max_height = 25,
                     rel_heights = c(2,1),
                     palette='RdYlBu') {
  
  
  #Pulling out dimensions to test for matrix type
  row_test = dim(cont_mat1)[1]
  col_test = dim(cont_mat1)[2]
  
  if (row_test == col_test) {
    if (all(is.finite(cont_mat1)) == FALSE) {
      stop("Contact matrix 1 contains non-numeric entries")
    }
    
    if (all(is.finite(cont_mat2)) == FALSE) {
      stop("Contact matrix 2 contains non-numeric entries")
    }
  }
  
  if (col_test == 3) {
    
    
    #Convert sparse matrix to n x n matrix
    
    message("Converting to n x n matrix")
    
    if (nrow(cont_mat1) == 1) {
      stop("Matrix 1 is too small to convert to full")
    }
    
    if (nrow(cont_mat2) == 1) {
      stop("Matrix 2 is too small to convert to full")
    }
    
    cont_mat1 = HiCcompare::sparse2full(cont_mat1)
    cont_mat2 = HiCcompare::sparse2full(cont_mat2)
    
    if (all(is.finite(cont_mat1)) == FALSE) {
      stop("Contact matrix 1 contains non-numeric entries")
    }
    
    if (all(is.finite(cont_mat2)) == FALSE) {
      stop("Contact matrix 2 contains non-numeric entries")
    }
    if (resolution == "auto") {
      message("Estimating resolution")
      resolution = as.numeric(names(table(as.numeric(colnames(cont_mat1))-
                                            lag(
                                              as.numeric(
                                                colnames(cont_mat1)
                                              ))))[1]
      )
    }
    
  } else if (col_test-row_test == 3) {
    
    message("Converting to n x n matrix")
    
    #Find the start coordinates based on the second column of the
    #bed file portion of matrix
    
    start_coords = cont_mat1[,2]
    
    #Calculate resolution based on given bin size in bed file
    
    resolution = as.numeric(cont_mat1[1,3])-as.numeric(cont_mat1[1,2])
    
    #Remove bed file portion
    
    cont_mat1 = as.matrix(cont_mat1[,-c(seq_len(3))])
    cont_mat2 = as.matrix(cont_mat2[,-c(seq_len(3))])
    
    if (all(is.finite(cont_mat1)) == FALSE) {
      stop("Contact matrix 1 contains non-numeric entries")
    }
    
    if (all(is.finite(cont_mat2)) == FALSE) {
      stop("Contact matrix 2 contains non-numeric entries")
    }
    
    #Make column names correspond to bin start
    
    colnames(cont_mat1) = start_coords
    colnames(cont_mat2) = start_coords
    
    
  } else if (col_test!=3 & (row_test != col_test) & (col_test-row_test != 3)) {
    
    #Throw error if matrix does not correspond to known matrix type
    
    stop("Contact matrix must be sparse or n x n or n x (n+3)!")
    
  } else if ( (resolution == "auto") & (col_test-row_test == 0) ) {
    message("Estimating resolution")
    
    #Estimating resolution based on most common distance between loci
    
    resolution = as.numeric(names(table(as.numeric(colnames(cont_mat1))-
                                          lag(
                                            as.numeric(colnames(cont_mat1))
                                          )))[1])
  }
  
  if (show_types == FALSE) {
    tad_diff$TAD_Frame = tad_diff$TAD_Frame %>%
      mutate(Differential = ifelse(Type == "Non-Overlap", "Non-Overlap", Differential))
    bed_coords = tad_diff$TAD_Frame %>% dplyr::select(start=Boundary, Enriched_In, Type = Differential)
    
  } else {
    bed_coords = tad_diff$TAD_Frame %>% dplyr::select(start=Boundary, Enriched_In, Type = Type)
    
  }
  
  present_coords_1 = as.numeric(colnames(cont_mat1))<=end_coord & as.numeric(colnames(cont_mat1))>=start_coord
  present_coords_2 = as.numeric(colnames(cont_mat2))<=end_coord & as.numeric(colnames(cont_mat2))>=start_coord
  
  tad_mat_1 = cont_mat1[present_coords_1,present_coords_1]
  tad_mat_2 = cont_mat2[present_coords_2,present_coords_2]
  
  #bed_coords = data.frame(start = match(bed_coords$start, as.numeric(colnames(cont_mat1))), end = match(bed_coords$end, as.numeric(colnames(cont_mat1))))
  
  
  # Make a triangle
  
  tad_mat_1[lower.tri(tad_mat_1)] = NA
  
  tad_mat_1 = as.data.frame(tad_mat_1)
  
  tad_mat_2[lower.tri(tad_mat_2)] = NA
  
  tad_mat_2 = as.data.frame(tad_mat_2)
  
  
  #Reshaping
  
  tad_mat_1$regions = as.numeric(gsub("X", "", colnames(tad_mat_1)))
  tad_mat_2$regions = as.numeric(gsub("X", "", colnames(tad_mat_2)))
  
  #tad_mat$boundary = ifelse(tad_mat$regions %in% bed$start, 1, 0)
  
  #tad_mat$boundary2 = ifelse(tad_mat$regions %in% bed$end, 1, 0)
  
  tad_mat_1 = na.omit(reshape2::melt(tad_mat_1, 'regions', variable_name='location'))
  tad_mat_2 = na.omit(reshape2::melt(tad_mat_2, 'regions', variable_name='location'))
  
  tad_mat_1$variable = as.numeric(gsub("X", "", tad_mat_1$variable))
  tad_mat_2$variable = as.numeric(gsub("X", "", tad_mat_2$variable))
  
  
  if ( (nrow(tad_mat_1)==0) | nrow(tad_mat_2)==0) {
    stop("TAD boundaries missing from at least one matrix")
  }
  colnames(tad_mat_1) = colnames(tad_mat_2) = c("start1", "start2", "value") 
  
  tad_mat_1$orig_regx = tad_mat_1$start1
  tad_mat_1$orig_regy = tad_mat_1$start2
  
  tad_mat_2$orig_regx = tad_mat_2$start1
  tad_mat_2$orig_regy = tad_mat_2$start2
  
  tad_mat_1 = .rotate(tad_mat_1, 45)
  tad_mat_2 = .rotate(tad_mat_2, 45)
  
  
  tad_mat_1$boundary_start = ifelse(tad_mat_1$orig_regx %in% bed_coords$start & (tad_mat_1$start2 == 0), 1, 0)
  tad_mat_1$boundary_end = ifelse(tad_mat_1$orig_regx %in% bed_coords$start & (tad_mat_1$start2 == 0), 1, 0)
  
  tad_mat_2$boundary_start = ifelse(tad_mat_2$orig_regx %in% bed_coords$start & (tad_mat_2$start2 == 0), 1, 0)
  tad_mat_2$boundary_end = ifelse(tad_mat_2$orig_regx %in% bed_coords$start & (tad_mat_2$start2 == 0), 1, 0)
  
  #bound_coords1 = cbind(plot_domain1[-nrow(plot_domain1),3], c(plot_domain1[2:nrow(plot_domain1), 2]))
  #bound_coords2 = cbind(plot_domain2[-nrow(plot_domain2),3], c(plot_domain2[2:nrow(plot_domain2), 2]))
  
  #Creating coordinates for the triangle
  
  trans_start_1 = (tad_mat_1 %>% filter(boundary_start == 1)) %>% dplyr::select(orig_regx, start1)
  trans_start_1 = left_join(bed_coords, trans_start_1, by = c("start" = "orig_regx"))
  
  #Save mappings
  
  cat_map = trans_start_1 %>% dplyr::select(Enriched_In, Type, start1)
  
  trans_start_1 = trans_start_1$start1
  
  trans_end_1 = (tad_mat_1 %>% filter(boundary_end == 1)) %>% dplyr::select(orig_regx, start1)
  trans_end_1 = left_join(bed_coords, trans_end_1, by = c("start" = "orig_regx"))
  trans_end_1 = trans_end_1$start1
  
  #Part 2
  
  trans_start_2 = (tad_mat_2 %>% filter(boundary_start == 1)) %>% dplyr::select(orig_regx, start1)
  trans_start_2 = left_join(bed_coords, trans_start_2, by = c("start" = "orig_regx"))
  trans_start_2 = trans_start_2$start1
  
  trans_end_2 = (tad_mat_2 %>% filter(boundary_end == 1)) %>% dplyr::select(orig_regx, start1)
  trans_end_2 = left_join(bed_coords, trans_end_2, by = c("start" = "orig_regx"))
  trans_end_2 = trans_end_2$start1
  
  #Part 1
  mid_points_1 = (trans_start_1+trans_end_1)/2
  
  d1_x_1 = c(trans_start_1, mid_points_1, trans_end_1)
  
  d1_y_1 = c(rep(0, length(d1_x_1)/3), (trans_end_1-trans_start_1)/2, rep(0, length(d1_x_1)/3))
  
  #Part 2
  
  mid_points_2 = (trans_start_2+trans_end_2)/2
  
  d1_x_2 = c(trans_start_2, mid_points_2, trans_end_2)
  
  d1_y_2 = c(rep(0, length(d1_x_2)/3), (trans_end_2-trans_start_2)/2, rep(0, length(d1_x_2)/3))
  
  #Adding ID variables to each matrix to get in proper form for geom_polygon and combining the vectors of x and y axes
  
  d1_triangle = cbind.data.frame(id = rep(seq_len((length(d1_x_1))/3), 3), x = d1_x_1, y = d1_y_1)
  
  d1_triangle = left_join(d1_triangle,cat_map %>%
                            filter(!is.na(start1)),
                          by = c("x" = "start1"))
  
  #Extra plot
  tad_comb = bind_rows(tad_mat_1, tad_mat_2 %>% mutate(start2 = -start2))
  
  track = tad_diff$Boundary_Scores 
  #Join track with transformed matrix
  track = left_join(track %>% 
                      dplyr::select(Boundary, TAD_Score1,
                                    TAD_Score2, Gap_Score), 
                    tad_mat_1 %>% filter(start2==0) %>%
                      dplyr::select(start1, orig_regx),
                    by = c("Boundary" = "orig_regx"))
  #Select only the regions that are present
  track  = track %>% dplyr::filter(!is.na(start1)) %>%
    dplyr::select(start1, TAD_Score1:Gap_Score)
  track = reshape2::melt(track, id.var = "start1")
  
  #Some renaming for prettier plotting
  track = track %>% mutate(variable = ifelse(variable == 
                                              "TAD_Score1", 
                                             "Boundary Score 1",
                                             ifelse(variable == 
                                                    "TAD_Score2",
                                                    "Boundary Score 2", 
                                                    "Differential Boundary Score"
                                             )))
  
  Lines = data.frame(variable = c("Boundary Score 1",
                                  "Boundary Score 2",
                                  "Differential Boundary Score",
                                  "Differential Boundary Score"),
                     line_spot = c(1.5,1.5,2,-2))
  
  track_plot = ggplot(track, aes(x = start1, 
                                 y=value,
                                 fill=variable)) +
    geom_line() + facet_wrap(~variable, nrow = 3)  +
    geom_hline(data = Lines, aes(yintercept = line_spot), 
               linetype="dashed", color="red") + 
    labs(y="") +
    theme(axis.title.x=element_blank(),
          axis.text.x=element_blank(),
          axis.ticks.x=element_blank())
    
  
  #Getting the desired order of labels
  
  if (show_types) {
  
  d1_triangle = d1_triangle %>% 
    mutate(Type = ifelse(Type == "Non-Overlap", "Non-Differential", Type))
  d1_triangle = d1_triangle %>% mutate(Type = factor(Type, 
                                                     levels = c("Non-Differential",
                                                                "Non-Overlap",
                                                                "Strength Change",
                                                                "Merge",
                                                                "Split",
                                                                "Shifted",
                                                                "Differential",
                                                                "Complex")))
  #Hard coding colors
  
  colors = c("black", "gray", "red", "yellow", "orange", "green", "blue")
  names(colors) =   c("Non-Differential",
                      "Non-Overlap",
                      "Strength Change",
                      "Merge",
                      "Split",
                      "Shifted",
                      "Complex")
  }

  #Replacing shifted with differential when appropriate
  
  
  #Set heatmap palette
  
   if (show_types == FALSE) {
     
     #Setting simplified colors for diffTAD
     d1_triangle = d1_triangle %>% 
       mutate(Type = ifelse(Type == "Shifted", "Differential", Type)) %>%
       mutate(Type = factor(Type,  
                            levels = c("Non-Differential", "Non-Overlap", "Differential")))
     
     colors = c("black", "gray", "red")
     names(colors) =   c("Non-Differential",
                         "Non-Overlap",
                         "Differential")
   }
  
  if (!is.null(pre_tad)) {
    
    pre_tad = lapply(pre_tad, as.data.frame)
    
    bed_coords1 = pre_tad[[1]]
    bed_coords2 = pre_tad[[2]]
    
    #Get triangles
    tads1 = .Make_Triangles(cont_mat=as.data.frame(cont_mat1), 
                            bed=bed_coords1, resolution=resolution,
                            start_coord=start_coord,
                            end_coord=end_coord) %>% filter(complete.cases(.))
    
    tads2 = .Make_Triangles(cont_mat=as.data.frame(cont_mat2), 
                            bed=bed_coords2, resolution=resolution,
                            start_coord=start_coord,
                            end_coord=end_coord) %>% filter(complete.cases(.))
    
  
    
    #Plotting the contact matrix

    if (length(palette) == 1) {
    plot_3 = ggplot(tad_comb, aes(start1, start2)) +
      theme_bw() +
      xlab('Coordinates') +
      ylab('Coordinates')   + geom_tile(data=tad_comb, 
      aes(x = start1, y = start2, fill =log2(value+.25))) +
      scale_fill_distiller(palette = palette, values = c(0, .4, 1)) +
      theme(axis.text.x=element_text(angle=90),
            axis.ticks=element_blank(),
            axis.line=element_blank(),
            panel.border=element_blank(),
            panel.grid.major=element_line(color='#eeeeee'))  +  
      geom_point(data = d1_triangle %>% filter(!is.na(Type)), aes(x = x, y = y, 
                                                                  color = Type), 
                 fill = NA, size =  point_size)  +
      scale_color_manual(values=colors) +  
      geom_polygon(data = tads1 ,
                   aes(x = x, y = y, group = id), 
                   color = "black", fill = NA, size = 1) +  
      geom_polygon(data = tads2 ,
                   aes(x = x, y = -y, group = id), 
                   color = "black", fill = NA, size = 1) + 
      coord_cartesian(ylim = c(-max(tads1$y, tads2$y),max(tads1$y, tads2$y)))+
      labs(fill="Log2(Contacts)") +
      theme(axis.title.x=element_blank(),
            axis.text.x=element_blank(),
            axis.ticks.x=element_blank())
    } else {
      plot_3 = ggplot(tad_comb, aes(start1, start2)) +
        theme_bw() +
        xlab('Coordinates') +
        ylab('Coordinates')   + geom_tile(data=tad_comb, 
                                          aes(x = start1, y = start2, fill =log2(value+.25))) +
        scale_fill_gradientn(colors = palette) +
        theme(axis.text.x=element_text(angle=90),
              axis.ticks=element_blank(),
              axis.line=element_blank(),
              panel.border=element_blank(),
              panel.grid.major=element_line(color='#eeeeee'))  +  
        geom_point(data = d1_triangle %>% filter(!is.na(Type)), aes(x = x, y = y, 
                                                                    color = Type), 
                   fill = NA, size =  point_size)  +
        scale_color_manual(values=colors) +  
        geom_polygon(data = tads1 ,
                     aes(x = x, y = y, group = id), 
                     color = "black", fill = NA, size = 1) +  
        geom_polygon(data = tads2 ,
                     aes(x = x, y = -y, group = id), 
                     color = "black", fill = NA, size = 1) + 
        coord_cartesian(ylim = c(-max(tads1$y, tads2$y),max(tads1$y, tads2$y)))+
        labs(fill="Log2(Contacts)") +
        theme(axis.title.x=element_blank(),
              axis.text.x=element_blank(),
              axis.ticks.x=element_blank())
    }
      
    leg = ggpubr::get_legend(plot_3) 
    } else {
  
    max_coord = unique(abs(
      tad_comb$start2[which(
        ((tad_comb$orig_regy-tad_comb$orig_regx)/resolution )==max_height )]))
                       
    if (length(palette) == 1) {
      #Getting coordinate of 25th highest coordinate
      
    plot_3 = ggplot(tad_comb, aes(start1, start2)) +
      theme_bw() +
      xlab('Coordinates') +
      ylab('Coordinates')   + geom_tile(data=tad_comb, aes(x = start1, y = start2, fill =log2(value+.25))) + #geom_point(aes(color =log2(value+.25)), size = 8) + 
      scale_fill_distiller(palette = palette, values = c(0, .4, 1)) +
      theme(axis.text.x=element_text(angle=90),
            axis.ticks=element_blank(),
            axis.line=element_blank(),
            panel.border=element_blank(),
            panel.grid.major=element_line(color='#eeeeee'))  +  
      geom_point(data = d1_triangle %>% filter(!is.na(Type)), aes(x = x, y = y, color = Type), 
                 fill = NA, size = point_size) +
      scale_color_manual(values=colors) + labs(fill="Log2(Contacts)") +
      coord_cartesian(ylim = c(-max_coord,
                               max_coord)) +
      theme(axis.title.x=element_blank(),
            axis.text.x=element_blank(),
            axis.ticks.x=element_blank())
    } else {
      plot_3 = ggplot(tad_comb, aes(start1, start2)) +
        theme_bw() +
        xlab('Coordinates') +
        ylab('Coordinates')   + geom_tile(data=tad_comb, 
                                          aes(x = start1, y = start2, fill =log2(value+.25))) +
        scale_fill_gradientn(colors = palette) +
        theme(axis.text.x=element_text(angle=90),
              axis.ticks=element_blank(),
              axis.line=element_blank(),
              panel.border=element_blank(),
              panel.grid.major=element_line(color='#eeeeee'))  +  
        geom_point(data = d1_triangle %>% filter(!is.na(Type)), aes(x = x, y = y, 
                                                                    color = Type), 
                   fill = NA, size =  point_size) +
        coord_cartesian(ylim = c(-max_coord,
                                 max_coord)) +
        scale_color_manual(values=colors) +  
        geom_polygon(data = tads1 ,
                     aes(x = x, y = y, group = id), 
                     color = "black", fill = NA, size = 1) +  
        geom_polygon(data = tads2 ,
                     aes(x = x, y = -y, group = id), 
                     color = "black", fill = NA, size = 1) + 
        coord_cartesian(ylim = c(-max(orig_regy, orig_regy)))+
        labs(fill="Log2(Contacts)") +
        theme(axis.title.x=element_blank(),
              axis.text.x=element_blank(),
              axis.ticks.x=element_blank())
    }
 
    
    leg = ggpubr::get_legend(plot_3) 
  }  
  arranged_plot=cowplot::plot_grid(cowplot::plot_grid(plot_3 +
                                     guides(fill=FALSE, 
                                            color=FALSE),  
                                   track_plot, ncol=1,
                                   align = "v", rel_heights = rel_heights),
                                   cowplot::plot_grid(leg, ncol=1), 
                                   rel_widths = c(1,.2), align="h")
  
  return(arranged_plot)
}



.rotate = function(df, degree) {
  dfr = df
  degree = pi * degree / 180
  l = sqrt(df$start1^2 + df$start2^2)
  teta = atan(df$start2 / df$start1)
  dfr$start1 = round(l * cos(teta - degree))
  dfr$start2 = round(l * sin(teta - degree))
  return(dfr)
}

.Make_Triangles = function(bed, cont_mat, resolution, start_coord, end_coord) {
  
  bed_coords = bed %>%filter(start>=start_coord) %>% filter(end<=end_coord) %>% dplyr::select(start,end)
  
  present_coords = as.numeric(colnames(cont_mat))<=end_coord & as.numeric(colnames(cont_mat))>=start_coord
  
  tad_mat = cont_mat[present_coords,present_coords]
  
  # Make a triangle
  
  tad_mat[lower.tri(tad_mat)] = NA
  
  tad_mat = as.data.frame(tad_mat)
  
  #Reshaping
  
  tad_mat$regions = as.numeric(gsub("X", "", colnames(tad_mat)))
  #tad_mat$boundary = ifelse(tad_mat$regions %in% bed$start, 1, 0)
  
  #tad_mat$boundary2 = ifelse(tad_mat$regions %in% bed$end, 1, 0)
  
  
  tad_mat = na.omit(reshape2::melt(tad_mat, 'regions', variable_name='location'))
  
  tad_mat$variable = as.numeric(gsub("X", "", tad_mat$variable))
  
  if (nrow(tad_mat)==0) {
    stop("TAD boundaries missing from at least one matrix")
  }
  
  colnames(tad_mat) = c("start1", "start2", "value") 
  
  tad_mat$orig_regx = tad_mat$start1
  tad_mat$orig_regy = tad_mat$start2
  
  
  tad_mat = .rotate(tad_mat, 45)
  
  tad_mat$boundary_start = ifelse(tad_mat$orig_regx %in% bed$start & (tad_mat$start2 == 0), 1, 0)
  tad_mat$boundary_end = ifelse(tad_mat$orig_regx %in% bed$end & (tad_mat$start2 == 0), 1, 0)
  
  
  #bound_coords1 = cbind(plot_domain1[-nrow(plot_domain1),3], c(plot_domain1[2:nrow(plot_domain1), 2]))
  #bound_coords2 = cbind(plot_domain2[-nrow(plot_domain2),3], c(plot_domain2[2:nrow(plot_domain2), 2]))
  
  #Creating coordinates for the triangle
  
  trans_start = (tad_mat %>% filter(boundary_start == 1)) %>% dplyr::select(orig_regx, start1)
  trans_start = left_join(bed_coords, trans_start, by = c("start" = "orig_regx"))
  trans_start = trans_start$start1
  
  trans_end = (tad_mat %>% filter(boundary_end == 1)) %>% dplyr::select(orig_regx, start1)
  trans_end = left_join(bed_coords, trans_end, by = c("end" = "orig_regx"))
  trans_end = trans_end$start1
  
  mid_points = (trans_start+trans_end)/2
  
  d1_x = c(trans_start, mid_points, trans_end)
  
  d1_y = c(rep(0, length(d1_x)/3), (trans_end-trans_start)/2, rep(0, length(d1_x)/3))
  
  #Adding ID variables to each matrix to get in proper form for geom_polygon and combining the vectors of x and y axes
  
  d1_triangle = cbind.data.frame(id = rep(seq_len((length(d1_x)/3)), 3), x = d1_x, y = d1_y)
  return(d1_triangle)
}
